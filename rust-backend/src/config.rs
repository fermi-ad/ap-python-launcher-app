use std::env;

#[derive(Clone, Debug)]
pub struct Config {
    pub harbor_base_url: String,
    pub harbor_project: String,
    pub harbor_username: Option<String>,
    pub harbor_password: Option<String>,

    pub kubeconfig_content: Option<String>,
    pub workload_namespace: String,

    pub app_target_port: u16,
    pub lb_port: u16,
    pub lb_annotations_json: Option<String>,

    pub port: u16,
}

impl Config {
    pub fn from_env() -> anyhow::Result<Self> {
        let harbor_base_url = env::var("AP_HARBOR_BASE_URL")
            .unwrap_or_else(|_| "https://adregistry.fnal.gov".to_string());
        let harbor_project =
            env::var("AP_HARBOR_PROJECT").unwrap_or_else(|_| "ap-python".to_string());
        let harbor_username = env::var("AP_HARBOR_USERNAME").ok();
        let harbor_password = env::var("AP_HARBOR_PASSWORD").ok();

        let kubeconfig_content = env::var("AP_KUBECONFIG").ok();
        let workload_namespace =
            env::var("AP_WORKLOAD_NAMESPACE").unwrap_or_else(|_| "ap-python".to_string());

        let app_target_port: u16 = env::var("AP_APP_TARGET_PORT")
            .unwrap_or_else(|_| "14500".to_string())
            .parse()?;
        let lb_port: u16 = env::var("AP_LB_PORT")
            .unwrap_or_else(|_| "80".to_string())
            .parse()?;
        let lb_annotations_json = env::var("AP_LB_ANNOTATIONS_JSON").ok();

        let port: u16 = env::var("AP_PORT")
            .or_else(|_| env::var("PORT"))
            .unwrap_or_else(|_| "8000".to_string())
            .parse()?;

        Ok(Self {
            harbor_base_url,
            harbor_project,
            harbor_username,
            harbor_password,
            kubeconfig_content,
            workload_namespace,
            app_target_port,
            lb_port,
            lb_annotations_json,
            port,
        })
    }

    pub fn mock_mode() -> bool {
        matches!(
            env::var("AP_MOCK_MODE")
                .unwrap_or_default()
                .to_ascii_lowercase()
                .as_str(),
            "1" | "true" | "yes"
        )
    }
}
