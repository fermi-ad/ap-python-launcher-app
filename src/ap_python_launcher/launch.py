from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import json
import random
import tempfile
from typing import NamedTuple
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
    service_port: int


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


class KubeLauncher:
    def __init__(
        self,
        namespace: str,
        *,
        kubeconfig_content: str | None = None,
        kubeconfig_path: str | None = None,
        app_target_port: int = 14500,
        lb_port: int = 80,
        lb_annotations_json: str | None = None,
        shared_lb_ip: str | None = None,
        shared_lb_annotations_json: str = '{"metallb.io/allow-shared-ip": "ap-python-launcher"}',
        shared_lb_port_range_start: int = 30000,
        shared_lb_port_range_end: int = 39999,
    ):
        if kubeconfig_content:
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8") as f:
                f.write(kubeconfig_content)
                f.flush()
                config.load_kube_config(config_file=f.name)
        elif kubeconfig_path:
            config.load_kube_config(config_file=kubeconfig_path)
        else:
            try:
                config.load_incluster_config()
            except Exception:
                config.load_kube_config()

        self.namespace = namespace
        self.app_target_port = app_target_port
        self.lb_port = lb_port
        self.lb_annotations_json = lb_annotations_json
        self.shared_lb_ip = shared_lb_ip
        self.shared_lb_annotations_json = shared_lb_annotations_json
        self.shared_lb_port_range_start = shared_lb_port_range_start
        self.shared_lb_port_range_end = shared_lb_port_range_end
        self.batch = client.BatchV1Api()
        self.core = client.CoreV1Api()

    def _get_canonical_shared_lb_ip(self) -> str | None:
        if self.shared_lb_ip:
            return self.shared_lb_ip

        selector = "app.kubernetes.io/managed-by=ap-python-launcher"
        services = self.core.list_namespaced_service(
            namespace=self.namespace, label_selector=selector
        )

        class _Candidate(NamedTuple):
            timestamp: datetime
            ip: str

        candidates: list[_Candidate] = []

        for service in services.items:
            meta = getattr(service, "metadata", None)

            spec = getattr(service, "spec", None)
            status = getattr(service, "status", None)

            spec_ip = getattr(spec, "load_balancer_ip", None) if spec else None
            ingress = (
                getattr(getattr(status, "load_balancer", None), "ingress", None)
                if status
                else None
            )
            status_ip = None
            if ingress:
                first = ingress[0]
                status_ip = getattr(first, "ip", None) or getattr(
                    first, "hostname", None
                )

            ip = spec_ip if isinstance(spec_ip, str) and spec_ip else None
            if not ip and isinstance(status_ip, str) and status_ip:
                ip = status_ip
            if not ip:
                continue

            timestamp = getattr(meta, "creation_timestamp", None) if meta else None
            if not isinstance(timestamp, datetime):
                continue

            candidates.append(_Candidate(timestamp=timestamp, ip=ip))

        if not candidates:
            return None

        try:
            return min(candidates, key=lambda x: x.timestamp).ip
        except TypeError:
            # Some tests use MagicMocks for timestamps; fall back to first candidate.
            return candidates[0].ip

    def _allocate_service_port(self, *, launch_id: str) -> int:
        shared_ip = self._get_canonical_shared_lb_ip()
        filter_by_ip = shared_ip is not None

        start = self.shared_lb_port_range_start
        end = self.shared_lb_port_range_end
        if start <= 0 or end <= 0 or end < start:
            raise ValueError(
                "Invalid shared LB port range; expected AP_SHARED_LB_PORT_RANGE_START <= AP_SHARED_LB_PORT_RANGE_END and both > 0"
            )

        selector = "app.kubernetes.io/managed-by=ap-python-launcher"
        services = self.core.list_namespaced_service(
            namespace=self.namespace, label_selector=selector
        )

        used: set[int] = set()
        for service in services.items:
            spec = getattr(service, "spec", None)
            if not spec:
                continue
            if filter_by_ip and getattr(spec, "load_balancer_ip", None) != shared_ip:
                continue
            ports = getattr(spec, "ports", None) or []
            for p in ports:
                port = getattr(p, "port", None)
                if isinstance(port, int):
                    used.add(port)

        candidates = [p for p in range(start, end + 1) if p not in used]
        if not candidates:
            raise LaunchLimitExceededError(
                f"No free ports available in range {start}-{end} for shared IP {shared_ip or '<dynamic>'}"
            )

        return random.choice(candidates)

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
                # Keep job records 24 hours after completion
                ttl_seconds_after_finished=24 * 60 * 60,
                # 24-hour hard timeout for running jobs
                active_deadline_seconds=24 * 60 * 60,
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
                                readiness_probe=client.V1Probe(
                                    http_get=client.V1HTTPGetAction(
                                        path="/",
                                        port=self.app_target_port,
                                    ),
                                    initial_delay_seconds=5,
                                    period_seconds=3,
                                    failure_threshold=10,
                                ),
                            )
                        ],
                    ),
                ),
            ),
        )

        created_job = self.batch.create_namespaced_job(
            namespace=self.namespace, body=job
        )

        # Create per-launch access point.
        service_name = self._service_name_for_launch(repo=repo, launch_id=launch_id)
        service_port = self._allocate_service_port(launch_id=launch_id)

        job_uid = getattr(getattr(created_job, "metadata", None), "uid", None)
        owner_refs = None
        if isinstance(job_uid, str) and job_uid:
            owner_refs = [
                client.V1OwnerReference(
                    api_version="batch/v1",
                    kind="Job",
                    name=job_name,
                    uid=job_uid,
                    block_owner_deletion=False,
                    controller=False,
                )
            ]

        self._ensure_loadbalancer_service(
            service_name=service_name,
            labels=labels,
            launch_id=launch_id,
            service_port=service_port,
            owner_references=owner_refs,
        )

        return LaunchResult(
            launch_id=launch_id,
            namespace=self.namespace,
            job_name=job_name,
            service_name=service_name,
            service_port=service_port,
        )

    def _ensure_loadbalancer_service(
        self,
        *,
        service_name: str,
        labels: dict[str, str],
        launch_id: str,
        service_port: int,
        owner_references: list[client.V1OwnerReference] | None = None,
    ) -> None:
        selector = {"ap-python.fnal.gov/launch-id": launch_id}
        annotations = self._parse_lb_annotations()

        try:
            extra = json.loads(self.shared_lb_annotations_json)
        except Exception as e:  # noqa: BLE001
            raise ValueError(f"Invalid AP_SHARED_LB_ANNOTATIONS_JSON: {e}") from e
        if not isinstance(extra, dict) or not all(
            isinstance(k, str) and isinstance(val, str) for k, val in extra.items()
        ):
            raise ValueError(
                "AP_SHARED_LB_ANNOTATIONS_JSON must be a JSON object of string->string"
            )
        annotations = {**annotations, **extra}

        svc_spec = client.V1ServiceSpec(
            type="LoadBalancer",
            selector=selector,
            ports=[
                client.V1ServicePort(
                    name="http",
                    port=service_port,
                    target_port=self.app_target_port,
                    protocol="TCP",
                )
            ],
            external_traffic_policy="Cluster",
        )

        if self.shared_lb_ip:
            svc_spec.load_balancer_ip = self.shared_lb_ip

        svc = client.V1Service(
            metadata=client.V1ObjectMeta(
                name=service_name,
                labels=labels,
                annotations=annotations,
                owner_references=owner_references,
            ),
            spec=svc_spec,
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

        ports = getattr(getattr(svc, "spec", None), "ports", None) or []
        service_port = None
        if ports:
            service_port = getattr(ports[0], "port", None)

        urls: list[str] = []
        for i in ingress:
            host = getattr(i, "hostname", None) or getattr(i, "ip", None)
            if not host:
                continue
            port = service_port if isinstance(service_port, int) else self.lb_port
            urls.append(f"http://{host}:{port}/")
        return urls

    def delete_job(self, *, launch_id: str) -> dict:
        selector = f"ap-python.fnal.gov/launch-id={launch_id}"
        jobs = self.batch.list_namespaced_job(
            namespace=self.namespace, label_selector=selector
        )
        if not jobs.items:
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

        return {"launchId": launch_id, "deleted": True, "jobName": job_name}

    def get_launch_status(self, *, launch_id: str) -> dict:
        # Find job by label selector
        selector = f"ap-python.fnal.gov/launch-id={launch_id}"
        jobs = self.batch.list_namespaced_job(
            namespace=self.namespace, label_selector=selector
        )
        if not jobs.items:
            return {"launchId": launch_id, "status": "NotFound"}

        job = jobs.items[0]

        # If the Job is in the process of being deleted, surface that explicitly.
        # This allows the UI to disable Connect while termination is in progress.
        deletion_ts = getattr(
            getattr(job, "metadata", None), "deletion_timestamp", None
        )

        if deletion_ts is not None:
            status = "Ending"
            s = job.status
        else:
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
        pod = pods.items[0] if pods.items else None
        pod_name = pod.metadata.name if pod else None

        # Only expose access URLs once the pod's readiness probe has passed.
        pod_ready = False
        if pod and pod.status and pod.status.conditions:
            for cond in pod.status.conditions:
                if cond.type == "Ready" and cond.status == "True":
                    pod_ready = True
                    break

        svc = self._get_service(launch_id=launch_id)
        service_name = svc.metadata.name if svc and svc.metadata else None
        urls = self._get_service_urls(svc) if svc else []

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
                "status": "Ready" if (urls and pod_ready) else "Pending",
                "urls": urls,
            },
        }
