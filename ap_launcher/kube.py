from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import tempfile
import uuid

from kubernetes import client, config


@dataclass(frozen=True)
class LaunchResult:
    launch_id: str
    namespace: str
    job_name: str


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


class KubeLauncher:
    def __init__(self, namespace: str, *, kubeconfig_content: str | None = None):
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
        self.batch = client.BatchV1Api()
        self.core = client.CoreV1Api()

    def create_job(
        self, *, image: str, repo: str, tag: str, requested_by: str | None = None
    ) -> LaunchResult:
        launch_id = str(uuid.uuid4())
        ts = _now_utc().strftime("%Y%m%d%H%M%S")
        safe_repo = repo.split("/")[-1].replace("_", "-").replace(".", "-")
        job_name = f"ap-python-{safe_repo}-{ts}".lower()[:63]

        labels = {
            "app.kubernetes.io/managed-by": "ap-python-launcher",
            "ap-python.fnal.gov/repo": repo.replace("/", "_"),
            "ap-python.fnal.gov/tag": tag,
            "ap-python.fnal.gov/launch-id": launch_id,
        }
        if requested_by:
            labels["ap-python.fnal.gov/requested-by"] = requested_by

        job = client.V1Job(
            metadata=client.V1ObjectMeta(name=job_name, labels=labels),
            spec=client.V1JobSpec(
                ttl_seconds_after_finished=3600,
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
                            )
                        ],
                    ),
                ),
            ),
        )

        self.batch.create_namespaced_job(namespace=self.namespace, body=job)
        return LaunchResult(
            launch_id=launch_id, namespace=self.namespace, job_name=job_name
        )

    def get_launch_status(self, *, launch_id: str) -> dict:
        # Find job by label selector
        selector = f"ap-python.fnal.gov/launch-id={launch_id}"
        jobs = self.batch.list_namespaced_job(
            namespace=self.namespace, label_selector=selector
        )
        if not jobs.items:
            return {"launchId": launch_id, "status": "NotFound"}

        job = jobs.items[0]
        s = job.status
        status = "Pending"
        if s.active:
            status = "Running"
        if s.succeeded:
            status = "Succeeded"
        if s.failed:
            status = "Failed"

        # Get a pod (if any) with same selector
        pods = self.core.list_namespaced_pod(
            namespace=self.namespace, label_selector=selector
        )
        pod_name = pods.items[0].metadata.name if pods.items else None

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
        }
