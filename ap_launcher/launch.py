from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import json
import tempfile
import uuid

from kubernetes import client, config
from kubernetes.client.exceptions import ApiException


MAX_JOBS_TOTAL = 45
MAX_JOBS_PER_APP = 10


class LaunchLimitExceededError(RuntimeError):
    pass


@dataclass(frozen=True)
class LaunchResult:
    launch_id: str
    namespace: str
    job_name: str
    service_name: str


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


class KubeLauncher:
    def __init__(
        self,
        namespace: str,
        *,
        kubeconfig_content: str | None = None,
        app_target_port: int = 14500,
        lb_port: int = 80,
        lb_annotations_json: str | None = None,
    ):
        # Prefer explicitly-provided kubeconfig content (useful when running in-cluster
        # but targeting a different cluster).
        if kubeconfig_content:
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8") as f:
                f.write(kubeconfig_content)
                f.flush()
                config.load_kube_config(config_file=f.name)
        else:
            # Prefer in-cluster config; fall back to default kubeconfig for local dev.
            try:
                config.load_incluster_config()
            except Exception:
                config.load_kube_config()

        self.namespace = namespace
        self.app_target_port = app_target_port
        self.lb_port = lb_port
        self.lb_annotations_json = lb_annotations_json
        self.batch = client.BatchV1Api()
        self.core = client.CoreV1Api()

    def _count_active_jobs(self, *, repo: str | None = None) -> int:
        selector = "app.kubernetes.io/managed-by=ap-python-launcher"
        if repo is not None:
            selector += f",ap-python.fnal.gov/repo={repo.replace('/', '_')}"

        jobs = self.batch.list_namespaced_job(
            namespace=self.namespace, label_selector=selector
        )

        active = 0
        for j in jobs.items:
            s = j.status
            if s is not None and s.active and s.active > 0:
                active += 1
        return active

    def _enforce_limits(self, *, repo: str) -> None:
        total_active = self._count_active_jobs(repo=None)
        if total_active >= MAX_JOBS_TOTAL:
            raise LaunchLimitExceededError(
                f"Total active job limit reached ({total_active}/{MAX_JOBS_TOTAL})"
            )

        per_app_active = self._count_active_jobs(repo=repo)
        if per_app_active >= MAX_JOBS_PER_APP:
            raise LaunchLimitExceededError(
                f"Active job limit reached for app '{repo}' ({per_app_active}/{MAX_JOBS_PER_APP})"
            )

    def _labels_for_launch(
        self, *, launch_id: str, repo: str, tag: str, requested_by: str | None
    ) -> dict[str, str]:
        labels = {
            "app.kubernetes.io/managed-by": "ap-python-launcher",
            "ap-python.fnal.gov/repo": repo.replace("/", "_"),
            "ap-python.fnal.gov/tag": tag,
            "ap-python.fnal.gov/launch-id": launch_id,
        }
        if requested_by:
            labels["ap-python.fnal.gov/requested-by"] = requested_by
        return labels

    def _service_name_for_launch(self, *, repo: str, launch_id: str) -> str:
        # Keep deterministic but short; Kubernetes name max is 63.
        safe_repo = repo.split("/")[-1].replace("_", "-").replace(".", "-")
        short_id = launch_id.split("-")[0]
        return f"appl-{safe_repo}-{short_id}".lower()[:63]

    def _parse_lb_annotations(self) -> dict[str, str]:
        if not self.lb_annotations_json:
            return {}
        try:
            v = json.loads(self.lb_annotations_json)
        except Exception as e:  # noqa: BLE001
            raise ValueError(f"Invalid AP_LB_ANNOTATIONS_JSON: {e}") from e
        if not isinstance(v, dict) or not all(
            isinstance(k, str) and isinstance(val, str) for k, val in v.items()
        ):
            raise ValueError(
                "AP_LB_ANNOTATIONS_JSON must be a JSON object of string->string"
            )
        return v

    def create_job(
        self, *, image: str, repo: str, tag: str, requested_by: str | None = None
    ) -> LaunchResult:
        # Enforce concurrency limits based on currently active Jobs.
        self._enforce_limits(repo=repo)

        launch_id = str(uuid.uuid4())
        ts = _now_utc().strftime("%Y%m%d%H%M%S")
        safe_repo = repo.split("/")[-1].replace("_", "-").replace(".", "-")
        job_name = f"ap-python-{safe_repo}-{ts}".lower()[:63]

        labels = self._labels_for_launch(
            launch_id=launch_id, repo=repo, tag=tag, requested_by=requested_by
        )

        job = client.V1Job(
            metadata=client.V1ObjectMeta(name=job_name, labels=labels),
            spec=client.V1JobSpec(
                ttl_seconds_after_finished=3600,
                active_deadline_seconds=86400,  # 24-hour hard timeout
                backoff_limit=0,
                template=client.V1PodTemplateSpec(
                    metadata=client.V1ObjectMeta(labels=labels),
                    spec=client.V1PodSpec(
                        restart_policy="Never",
                        containers=[
                            client.V1Container(
                                name="app",
                                image=image,
                                image_pull_policy="IfNotPresent",
                                ports=[
                                    client.V1ContainerPort(
                                        container_port=self.app_target_port
                                    )
                                ],
                                resources=client.V1ResourceRequirements(
                                    requests={"cpu": "50m", "memory": "256Mi"},
                                    limits={"cpu": "200m", "memory": "512Mi"},
                                ),
                            )
                        ],
                    ),
                ),
            ),
        )

        self.batch.create_namespaced_job(namespace=self.namespace, body=job)

        # Create per-launch access point.
        service_name = self._service_name_for_launch(repo=repo, launch_id=launch_id)
        self._ensure_loadbalancer_service(
            service_name=service_name, labels=labels, launch_id=launch_id
        )

        return LaunchResult(
            launch_id=launch_id,
            namespace=self.namespace,
            job_name=job_name,
            service_name=service_name,
        )

    def _ensure_loadbalancer_service(
        self, *, service_name: str, labels: dict[str, str], launch_id: str
    ) -> None:
        selector = {"ap-python.fnal.gov/launch-id": launch_id}
        annotations = self._parse_lb_annotations()

        svc = client.V1Service(
            metadata=client.V1ObjectMeta(
                name=service_name, labels=labels, annotations=annotations
            ),
            spec=client.V1ServiceSpec(
                type="LoadBalancer",
                selector=selector,
                ports=[
                    client.V1ServicePort(
                        name="http",
                        port=self.lb_port,
                        target_port=self.app_target_port,
                        protocol="TCP",
                    )
                ],
            ),
        )

        try:
            self.core.create_namespaced_service(namespace=self.namespace, body=svc)
        except ApiException as e:
            # If it already exists, treat as idempotent.
            if getattr(e, "status", None) != 409:
                raise

    def _get_service(self, *, launch_id: str) -> client.V1Service | None:
        selector = f"ap-python.fnal.gov/launch-id={launch_id}"
        svcs = self.core.list_namespaced_service(
            namespace=self.namespace, label_selector=selector
        )
        return svcs.items[0] if svcs.items else None

    def _get_service_urls(self, svc: client.V1Service) -> list[str]:
        if not svc.status or not svc.status.load_balancer:
            return []
        ingress = svc.status.load_balancer.ingress
        if not ingress:
            return []

        urls: list[str] = []
        for i in ingress:
            host = getattr(i, "hostname", None) or getattr(i, "ip", None)
            if not host:
                continue
            # Prefer http:// since this is raw LB access; TLS termination depends on infra.
            urls.append(f"http://{host}:{self.lb_port}/")
        return urls

    def _delete_service_for_launch(self, *, launch_id: str) -> bool:
        svc = self._get_service(launch_id=launch_id)
        if not svc:
            return False
        name = svc.metadata.name if svc.metadata and svc.metadata.name else None
        if not name:
            return False
        try:
            self.core.delete_namespaced_service(name=name, namespace=self.namespace)
        except ApiException as e:
            if getattr(e, "status", None) != 404:
                raise
        return True

    def delete_job(self, *, launch_id: str) -> dict:
        selector = f"ap-python.fnal.gov/launch-id={launch_id}"
        jobs = self.batch.list_namespaced_job(
            namespace=self.namespace, label_selector=selector
        )
        if not jobs.items:
            self._delete_service_for_launch(launch_id=launch_id)
            return {"launchId": launch_id, "deleted": False, "reason": "NotFound"}

        job = jobs.items[0]
        job_name = job.metadata.name
        try:
            self.batch.delete_namespaced_job(
                name=job_name,
                namespace=self.namespace,
                body=client.V1DeleteOptions(propagation_policy="Foreground"),
            )
        except ApiException as e:
            if getattr(e, "status", None) != 404:
                raise

        self._delete_service_for_launch(launch_id=launch_id)
        return {"launchId": launch_id, "deleted": True, "jobName": job_name}

    def get_launch_status(self, *, launch_id: str) -> dict:
        # Find job by label selector
        selector = f"ap-python.fnal.gov/launch-id={launch_id}"
        jobs = self.batch.list_namespaced_job(
            namespace=self.namespace, label_selector=selector
        )
        if not jobs.items:
            # Best-effort cleanup
            self._delete_service_for_launch(launch_id=launch_id)
            return {"launchId": launch_id, "status": "NotFound"}

        job = jobs.items[0]
        s = job.status
        status = "Pending"
        if s and s.active:
            status = "Running"
        if s and s.succeeded:
            status = "Succeeded"
        if s and s.failed:
            status = "Failed"

        # Get a pod (if any) with same selector
        pods = self.core.list_namespaced_pod(
            namespace=self.namespace, label_selector=selector
        )
        pod_name = pods.items[0].metadata.name if pods.items else None

        svc = self._get_service(launch_id=launch_id)
        service_name = svc.metadata.name if svc and svc.metadata else None
        urls = self._get_service_urls(svc) if svc else []

        # Cleanup service when job is no longer running, or pod disappeared.
        if status in {"Succeeded", "Failed"} or pod_name is None:
            self._delete_service_for_launch(launch_id=launch_id)
            svc = None
            service_name = None
            urls = []

        return {
            "launchId": launch_id,
            "namespace": self.namespace,
            "jobName": job.metadata.name,
            "podName": pod_name,
            "status": status,
            "startTime": s.start_time.isoformat() if s and s.start_time else None,
            "completionTime": s.completion_time.isoformat()
            if s and s.completion_time
            else None,
            "serviceName": service_name,
            "access": {
                "status": "Ready" if urls else "Pending",
                "urls": urls,
            },
        }
