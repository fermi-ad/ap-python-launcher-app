use std::sync::Arc;

use axum::{Json, Router, extract::State, routing::get, routing::post};
use serde_json::json;

use crate::{
    config::Config,
    errors::{ApiError, ApiResult},
    harbor::HarborClient,
    kube_launcher::KubeLauncher,
    models::{AppsResponse, BatchLaunchStatusRequest, LaunchRequest, LaunchResponse},
};

#[derive(Clone)]
pub struct AppState {
    pub cfg: Arc<Config>,
}

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/healthz", get(healthz))
        .route("/readyz", get(readyz))
        .route("/apps", get(apps))
        .route("/launch", post(launch))
        .route("/launch/status", post(batch_launch_status))
        .route(
            "/launch/:launch_id",
            get(launch_status).delete(delete_launch),
        )
        .with_state(state)
}

async fn healthz() -> Json<serde_json::Value> {
    Json(json!({"ok": true}))
}

async fn readyz(State(state): State<AppState>) -> ApiResult<Json<serde_json::Value>> {
    Ok(Json(json!({
        "ok": true,
        "harborProject": state.cfg.harbor_project,
        "workloadNamespace": state.cfg.workload_namespace,
    })))
}

async fn apps(State(state): State<AppState>) -> ApiResult<Json<AppsResponse>> {
    let hc = HarborClient::new(
        state.cfg.harbor_base_url.clone(),
        state.cfg.harbor_project.clone(),
        state.cfg.harbor_username.clone(),
        state.cfg.harbor_password.clone(),
    )?;

    let apps = hc.list_latest_apps().await?;

    Ok(Json(AppsResponse {
        source: "harbor".to_string(),
        project: state.cfg.harbor_project.clone(),
        apps,
    }))
}

async fn launch(
    State(state): State<AppState>,
    Json(body): Json<LaunchRequest>,
) -> ApiResult<Json<LaunchResponse>> {
    if body.repo.trim().is_empty() {
        return Err(ApiError::BadRequest("Missing/invalid repo".to_string()));
    }

    let hc = HarborClient::new(
        state.cfg.harbor_base_url.clone(),
        state.cfg.harbor_project.clone(),
        state.cfg.harbor_username.clone(),
        state.cfg.harbor_password.clone(),
    )?;

    let apps = hc.list_latest_apps().await?;
    let m = apps.into_iter().find(|a| a.repo == body.repo);
    let Some(m) = m else {
        return Err(ApiError::NotFound(format!("App not found: {}", body.repo)));
    };

    let registry_host = state
        .cfg
        .harbor_base_url
        .replace("https://", "")
        .replace("http://", "");
    let image = format!("{}/{repo}:{tag}", registry_host, repo = m.repo, tag = m.tag);

    let kl = KubeLauncher::new(
        state.cfg.workload_namespace.clone(),
        state.cfg.kubeconfig_content.clone(),
        state.cfg.kubeconfig_path.clone(),
        state.cfg.app_target_port,
        state.cfg.lb_port,
        state.cfg.lb_annotations_json.clone(),
        state.cfg.shared_lb_ip.clone(),
        state.cfg.shared_lb_annotations_json.clone(),
        state.cfg.shared_lb_port_range_start,
        state.cfg.shared_lb_port_range_end,
    )
    .await?;

    let res = kl
        .create_job(&image, &m.repo, &m.tag, None)
        .await
        .map_err(|e| {
            if e.to_string().contains("Total active job limit")
                || e.to_string().contains("Active job limit")
                || e.to_string().contains("No free ports")
            {
                ApiError::TooManyRequests(e.to_string())
            } else {
                ApiError::Anyhow(e)
            }
        })?;

    Ok(Json(LaunchResponse {
        launch_id: res.launch_id,
        job_name: res.job_name,
        service_name: res.service_name,
        namespace: res.namespace,
        tag: m.tag,
        access: crate::models::LaunchAccess {
            status: "Pending".to_string(),
            urls: vec![],
        },
    }))
}

async fn batch_launch_status(
    State(state): State<AppState>,
    Json(body): Json<BatchLaunchStatusRequest>,
) -> ApiResult<Json<serde_json::Value>> {
    if body.launch_ids.is_empty() || body.launch_ids.iter().any(|s| s.trim().is_empty()) {
        return Err(ApiError::BadRequest(
            "Missing/invalid launchIds; expected non-empty strings".to_string(),
        ));
    }

    let kl = KubeLauncher::new(
        state.cfg.workload_namespace.clone(),
        state.cfg.kubeconfig_content.clone(),
        state.cfg.kubeconfig_path.clone(),
        state.cfg.app_target_port,
        state.cfg.lb_port,
        state.cfg.lb_annotations_json.clone(),
        state.cfg.shared_lb_ip.clone(),
        state.cfg.shared_lb_annotations_json.clone(),
        state.cfg.shared_lb_port_range_start,
        state.cfg.shared_lb_port_range_end,
    )
    .await?;

    let mut launches = Vec::new();
    for id in body.launch_ids {
        launches.push(kl.get_launch_status(&id).await?);
    }

    Ok(Json(json!({"launches": launches})))
}

async fn launch_status(
    State(state): State<AppState>,
    axum::extract::Path(launch_id): axum::extract::Path<String>,
) -> ApiResult<Json<serde_json::Value>> {
    let kl = KubeLauncher::new(
        state.cfg.workload_namespace.clone(),
        state.cfg.kubeconfig_content.clone(),
        state.cfg.kubeconfig_path.clone(),
        state.cfg.app_target_port,
        state.cfg.lb_port,
        state.cfg.lb_annotations_json.clone(),
        state.cfg.shared_lb_ip.clone(),
        state.cfg.shared_lb_annotations_json.clone(),
        state.cfg.shared_lb_port_range_start,
        state.cfg.shared_lb_port_range_end,
    )
    .await?;

    Ok(Json(kl.get_launch_status(&launch_id).await?))
}

async fn delete_launch(
    State(state): State<AppState>,
    axum::extract::Path(launch_id): axum::extract::Path<String>,
) -> ApiResult<Json<serde_json::Value>> {
    let kl = KubeLauncher::new(
        state.cfg.workload_namespace.clone(),
        state.cfg.kubeconfig_content.clone(),
        state.cfg.kubeconfig_path.clone(),
        state.cfg.app_target_port,
        state.cfg.lb_port,
        state.cfg.lb_annotations_json.clone(),
        state.cfg.shared_lb_ip.clone(),
        state.cfg.shared_lb_annotations_json.clone(),
        state.cfg.shared_lb_port_range_start,
        state.cfg.shared_lb_port_range_end,
    )
    .await?;

    Ok(Json(kl.delete_job(&launch_id).await?))
}
