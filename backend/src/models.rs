use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct HarborRepo {
    pub repo: String,
    pub tag: String,
    #[serde(rename = "allTags")]
    pub all_tags: Vec<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AppsResponse {
    pub source: String,
    pub project: String,
    pub apps: Vec<HarborRepo>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct LaunchRequest {
    pub repo: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct LaunchResponse {
    #[serde(rename = "launchId")]
    pub launch_id: String,
    #[serde(rename = "jobName")]
    pub job_name: String,
    #[serde(rename = "serviceName")]
    pub service_name: String,
    pub namespace: String,
    pub tag: String,
    pub access: LaunchAccess,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct LaunchAccess {
    pub status: String,
    pub urls: Vec<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct BatchLaunchStatusRequest {
    #[serde(rename = "launchIds")]
    pub launch_ids: Vec<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct BatchLaunchStatusResponse {
    pub launches: Vec<serde_json::Value>,
}
