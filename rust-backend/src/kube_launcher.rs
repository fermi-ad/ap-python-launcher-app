use std::collections::BTreeMap;

use anyhow::Context;
use chrono::{DateTime, Utc};
use k8s_openapi::api::{
    batch::v1::{Job, JobSpec},
    core::v1::{
        Container, ContainerPort, HTTPGetAction, Pod, PodSpec, PodTemplateSpec, Probe,
        ResourceRequirements, Service, ServicePort, ServiceSpec,
    },
};
use kube::{
    Api, Client,
    api::{DeleteParams, ListParams, ObjectMeta, Patch, PatchParams, PostParams},
};
use serde_json::json;

pub const MAX_JOBS_TOTAL: i32 = 45;
pub const MAX_JOBS_PER_APP: i32 = 10;

#[derive(thiserror::Error, Debug)]
#[error("{0}")]
pub struct LaunchLimitExceededError(pub String);

#[derive(Clone, Debug)]
pub struct LaunchResult {
    pub launch_id: String,
    pub namespace: String,
    pub job_name: String,
    pub service_name: String,
}

#[derive(Clone)]
pub struct KubeLauncher {
    namespace: String,
    app_target_port: i32,
    lb_port: i32,
    lb_annotations_json: Option<String>,
    client: Client,
}

impl KubeLauncher {
    pub async fn new(
        namespace: String,
        kubeconfig_content: Option<String>,
        app_target_port: u16,
        lb_port: u16,
        lb_annotations_json: Option<String>,
    ) -> anyhow::Result<Self> {
        if kubeconfig_content.is_some() {
            tracing::warn!(
                "AP_KUBECONFIG content provided but not yet supported in Rust backend; using default kube config resolution"
            );
        }

        let client = Client::try_default().await?;

        Ok(Self {
            namespace,
            app_target_port: app_target_port as i32,
            lb_port: lb_port as i32,
            lb_annotations_json,
            client,
        })
    }

    pub fn parse_lb_annotations_json(
        lb_annotations_json: Option<&str>,
    ) -> anyhow::Result<BTreeMap<String, String>> {
        let Some(s) = lb_annotations_json else {
            return Ok(BTreeMap::new());
        };

        let v: serde_json::Value = serde_json::from_str(s)
            .with_context(|| format!("Invalid AP_LB_ANNOTATIONS_JSON: {s}"))?;

        let obj = v
            .as_object()
            .context("AP_LB_ANNOTATIONS_JSON must be a JSON object")?;

        let mut out = BTreeMap::new();
        for (k, v) in obj {
            let Some(vs) = v.as_str() else {
                anyhow::bail!("AP_LB_ANNOTATIONS_JSON must be a JSON object of string->string");
            };
            out.insert(k.clone(), vs.to_string());
        }

        Ok(out)
    }

    async fn count_active_jobs(&self, repo: Option<&str>) -> anyhow::Result<i32> {
        let api: Api<Job> = Api::namespaced(self.client.clone(), &self.namespace);

        let mut selector = "app.kubernetes.io/managed-by=ap-python-launcher".to_string();
        if let Some(repo) = repo {
            selector.push_str(",ap-python.fnal.gov/repo=");
            selector.push_str(&repo.replace('/', "_"));
        }

        let jobs = api
            .list(&ListParams::default().labels(&selector))
            .await
            .context("list jobs")?;

        let mut active = 0;
        for j in jobs.items {
            if let Some(s) = j.status {
                if let Some(a) = s.active {
                    if a > 0 {
                        active += 1;
                    }
                }
            }
        }

        Ok(active)
    }

    async fn enforce_limits(&self, repo: &str) -> Result<(), LaunchLimitExceededError> {
        let total_active = self.count_active_jobs(None).await.unwrap_or(0);
        if total_active >= MAX_JOBS_TOTAL {
            return Err(LaunchLimitExceededError(format!(
                "Total active job limit reached ({}/{})",
                total_active, MAX_JOBS_TOTAL
            )));
        }

        let per_app_active = self.count_active_jobs(Some(repo)).await.unwrap_or(0);
        if per_app_active >= MAX_JOBS_PER_APP {
            return Err(LaunchLimitExceededError(format!(
                "Active job limit reached for app '{}' ({}/{})",
                repo, per_app_active, MAX_JOBS_PER_APP
            )));
        }

        Ok(())
    }

    fn labels_for_launch(
        &self,
        launch_id: &str,
        repo: &str,
        tag: &str,
        requested_by: Option<&str>,
    ) -> BTreeMap<String, String> {
        let mut labels = BTreeMap::from([
            (
                "app.kubernetes.io/managed-by".to_string(),
                "ap-python-launcher".to_string(),
            ),
            (
                "ap-python.fnal.gov/repo".to_string(),
                repo.replace('/', "_"),
            ),
            ("ap-python.fnal.gov/tag".to_string(), tag.to_string()),
            (
                "ap-python.fnal.gov/launch-id".to_string(),
                launch_id.to_string(),
            ),
        ]);

        if let Some(r) = requested_by {
            labels.insert("ap-python.fnal.gov/requested-by".to_string(), r.to_string());
        }

        labels
    }

    fn service_name_for_launch(&self, repo: &str, launch_id: &str) -> String {
        let safe_repo = repo
            .split('/')
            .last()
            .unwrap_or(repo)
            .replace('_', "-")
            .replace('.', "-");
        let short_id = launch_id.split('-').next().unwrap_or(launch_id);
        let name = format!("appl-{}-{}", safe_repo, short_id).to_lowercase();
        name.chars().take(63).collect()
    }

    pub fn parse_lb_annotations(&self) -> anyhow::Result<BTreeMap<String, String>> {
        Self::parse_lb_annotations_json(self.lb_annotations_json.as_deref())
    }

    pub async fn create_job(
        &self,
        image: &str,
        repo: &str,
        tag: &str,
        requested_by: Option<&str>,
    ) -> Result<LaunchResult, anyhow::Error> {
        self.enforce_limits(repo)
            .await
            .map_err(|e| anyhow::anyhow!(e.to_string()))?;

        let launch_id = uuid::Uuid::new_v4().to_string();
        let ts = Utc::now().format("%Y%m%d%H%M%S").to_string();
        let safe_repo = repo
            .split('/')
            .last()
            .unwrap_or(repo)
            .replace('_', "-")
            .replace('.', "-");
        let job_name: String = format!("ap-python-{}-{}", safe_repo, ts)
            .to_lowercase()
            .chars()
            .take(63)
            .collect();

        let labels = self.labels_for_launch(&launch_id, repo, tag, requested_by);

        let job_api: Api<Job> = Api::namespaced(self.client.clone(), &self.namespace);

        let job = Job {
            metadata: ObjectMeta {
                name: Some(job_name.clone()),
                labels: Some(labels.clone()),
                ..Default::default()
            },
            spec: Some(JobSpec {
                ttl_seconds_after_finished: Some(24 * 60 * 60),
                active_deadline_seconds: Some(24 * 60 * 60),
                backoff_limit: Some(0),
                template: PodTemplateSpec {
                    metadata: Some(ObjectMeta {
                        labels: Some(labels.clone()),
                        ..Default::default()
                    }),
                    spec: Some(PodSpec {
                        restart_policy: Some("Never".to_string()),
                        containers: vec![Container {
                            name: "app".to_string(),
                            image: Some(image.to_string()),
                            image_pull_policy: Some("IfNotPresent".to_string()),
                            ports: Some(vec![ContainerPort {
                                container_port: self.app_target_port,
                                ..Default::default()
                            }]),
                            resources: Some(ResourceRequirements {
                                requests: Some(BTreeMap::from([
                                    (
                                        "cpu".to_string(),
                                        k8s_openapi::apimachinery::pkg::api::resource::Quantity(
                                            "50m".to_string(),
                                        ),
                                    ),
                                    (
                                        "memory".to_string(),
                                        k8s_openapi::apimachinery::pkg::api::resource::Quantity(
                                            "256Mi".to_string(),
                                        ),
                                    ),
                                ])),
                                limits: Some(BTreeMap::from([
                                    (
                                        "cpu".to_string(),
                                        k8s_openapi::apimachinery::pkg::api::resource::Quantity(
                                            "200m".to_string(),
                                        ),
                                    ),
                                    (
                                        "memory".to_string(),
                                        k8s_openapi::apimachinery::pkg::api::resource::Quantity(
                                            "512Mi".to_string(),
                                        ),
                                    ),
                                ])),
                                ..Default::default()
                            }),
                            readiness_probe: Some(Probe {
                                http_get: Some(HTTPGetAction {
                                    path: Some("/".to_string()),
                                    port: k8s_openapi::apimachinery::pkg::util::intstr::IntOrString::Int(
                                        self.app_target_port,
                                    ),
                                    ..Default::default()
                                }),
                                initial_delay_seconds: Some(5),
                                period_seconds: Some(3),
                                failure_threshold: Some(10),
                                ..Default::default()
                            }),
                            ..Default::default()
                        }],
                        ..Default::default()
                    }),
                },
                ..Default::default()
            }),
            ..Default::default()
        };

        job_api
            .create(&PostParams::default(), &job)
            .await
            .context("create job")?;

        let service_name = self.service_name_for_launch(repo, &launch_id);
        self.ensure_loadbalancer_service(&service_name, &labels, &launch_id)
            .await?;

        Ok(LaunchResult {
            launch_id: launch_id.clone(),
            namespace: self.namespace.clone(),
            job_name,
            service_name,
        })
    }

    async fn ensure_loadbalancer_service(
        &self,
        service_name: &str,
        labels: &BTreeMap<String, String>,
        launch_id: &str,
    ) -> anyhow::Result<()> {
        let svc_api: Api<Service> = Api::namespaced(self.client.clone(), &self.namespace);

        let annotations = self.parse_lb_annotations()?;

        let svc = Service {
            metadata: ObjectMeta {
                name: Some(service_name.to_string()),
                labels: Some(labels.clone()),
                annotations: if annotations.is_empty() {
                    None
                } else {
                    Some(annotations)
                },
                ..Default::default()
            },
            spec: Some(ServiceSpec {
                type_: Some("LoadBalancer".to_string()),
                selector: Some(BTreeMap::from([(
                    "ap-python.fnal.gov/launch-id".to_string(),
                    launch_id.to_string(),
                )])),
                ports: Some(vec![ServicePort {
                    name: Some("http".to_string()),
                    port: self.lb_port,
                    target_port: Some(
                        k8s_openapi::apimachinery::pkg::util::intstr::IntOrString::Int(
                            self.app_target_port,
                        ),
                    ),
                    protocol: Some("TCP".to_string()),
                    ..Default::default()
                }]),
                ..Default::default()
            }),
            ..Default::default()
        };

        let pp = PatchParams::apply("ap-python-launcher").force();
        let patch = Patch::Apply(json!(svc));

        svc_api
            .patch(service_name, &pp, &patch)
            .await
            .context("apply service")?;

        Ok(())
    }

    pub async fn delete_job(&self, launch_id: &str) -> anyhow::Result<serde_json::Value> {
        let job_api: Api<Job> = Api::namespaced(self.client.clone(), &self.namespace);
        let selector = format!("ap-python.fnal.gov/launch-id={}", launch_id);

        let jobs = job_api
            .list(&ListParams::default().labels(&selector))
            .await
            .context("list jobs")?;

        if jobs.items.is_empty() {
            self.delete_service_for_launch(launch_id).await.ok();
            return Ok(json!({"launchId": launch_id, "deleted": false, "reason": "NotFound"}));
        }

        let job = &jobs.items[0];
        let job_name = job.metadata.name.clone().unwrap_or_default();

        job_api
            .delete(
                &job_name,
                &DeleteParams {
                    propagation_policy: Some(kube::api::PropagationPolicy::Foreground),
                    ..Default::default()
                },
            )
            .await
            .ok();

        self.delete_service_for_launch(launch_id).await.ok();

        Ok(json!({"launchId": launch_id, "deleted": true, "jobName": job_name}))
    }

    pub async fn get_launch_status(&self, launch_id: &str) -> anyhow::Result<serde_json::Value> {
        let job_api: Api<Job> = Api::namespaced(self.client.clone(), &self.namespace);
        let pod_api: Api<Pod> = Api::namespaced(self.client.clone(), &self.namespace);
        let svc_api: Api<Service> = Api::namespaced(self.client.clone(), &self.namespace);

        let selector = format!("ap-python.fnal.gov/launch-id={}", launch_id);

        let jobs = job_api
            .list(&ListParams::default().labels(&selector))
            .await
            .context("list jobs")?;

        if jobs.items.is_empty() {
            self.delete_service_for_launch(launch_id).await.ok();
            return Ok(json!({"launchId": launch_id, "status": "NotFound"}));
        }

        let job = &jobs.items[0];

        let deletion_ts = job.metadata.deletion_timestamp.clone();

        let mut status = "Pending".to_string();
        let mut start_time: Option<DateTime<Utc>> = None;
        let mut completion_time: Option<DateTime<Utc>> = None;

        if deletion_ts.is_some() {
            status = "Ending".to_string();
        }

        if let Some(s) = &job.status {
            start_time = s.start_time.clone().map(|t| t.0);
            completion_time = s.completion_time.clone().map(|t| t.0);

            if deletion_ts.is_none() {
                if s.active.unwrap_or(0) > 0 {
                    status = "Running".to_string();
                }
                if s.succeeded.unwrap_or(0) > 0 {
                    status = "Succeeded".to_string();
                }
                if s.failed.unwrap_or(0) > 0 {
                    status = "Failed".to_string();
                }
            }
        }

        let pods = pod_api
            .list(&ListParams::default().labels(&selector))
            .await
            .context("list pods")?;
        let pod = pods.items.first();
        let pod_name = pod.and_then(|p| p.metadata.name.clone());

        let mut pod_ready = false;
        if let Some(p) = pod {
            if let Some(st) = &p.status {
                if let Some(conds) = &st.conditions {
                    for c in conds {
                        if c.type_ == "Ready" && c.status == "True" {
                            pod_ready = true;
                            break;
                        }
                    }
                }
            }
        }

        let svcs = svc_api
            .list(&ListParams::default().labels(&selector))
            .await
            .context("list services")?;
        let svc = svcs.items.first();
        let service_name = svc.and_then(|s| s.metadata.name.clone());

        let urls = service_urls(svc, self.lb_port);

        if status == "Succeeded" || status == "Failed" || status == "Ending" || pod_name.is_none() {
            self.delete_service_for_launch(launch_id).await.ok();
            return Ok(json!({
                "launchId": launch_id,
                "namespace": self.namespace,
                "jobName": job.metadata.name,
                "podName": pod_name,
                "status": status,
                "startTime": start_time.map(|t| t.to_rfc3339()),
                "completionTime": completion_time.map(|t| t.to_rfc3339()),
                "serviceName": null,
                "access": {"status": "Pending", "urls": []}
            }));
        }

        Ok(json!({
            "launchId": launch_id,
            "namespace": self.namespace,
            "jobName": job.metadata.name,
            "podName": pod_name,
            "status": status,
            "startTime": start_time.map(|t| t.to_rfc3339()),
            "completionTime": completion_time.map(|t| t.to_rfc3339()),
            "serviceName": service_name,
            "access": {
                "status": if !urls.is_empty() && pod_ready {"Ready"} else {"Pending"},
                "urls": urls,
            }
        }))
    }

    async fn delete_service_for_launch(&self, launch_id: &str) -> anyhow::Result<()> {
        let svc_api: Api<Service> = Api::namespaced(self.client.clone(), &self.namespace);
        let selector = format!("ap-python.fnal.gov/launch-id={}", launch_id);

        let svcs = svc_api
            .list(&ListParams::default().labels(&selector))
            .await
            .context("list services")?;

        if let Some(svc) = svcs.items.first() {
            if let Some(name) = &svc.metadata.name {
                svc_api.delete(name, &DeleteParams::default()).await.ok();
            }
        }

        Ok(())
    }
}

fn service_urls(svc: Option<&Service>, lb_port: i32) -> Vec<String> {
    let Some(svc) = svc else {
        return vec![];
    };

    let Some(status) = &svc.status else {
        return vec![];
    };

    let Some(lb) = &status.load_balancer else {
        return vec![];
    };

    let Some(ingress) = &lb.ingress else {
        return vec![];
    };

    let mut urls = Vec::new();
    for i in ingress {
        let host = i.hostname.clone().or_else(|| i.ip.clone());
        if let Some(h) = host {
            urls.push(format!("http://{}:{}/", h, lb_port));
        }
    }

    urls
}
