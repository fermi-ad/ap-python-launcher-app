use anyhow::Context;
use base64::Engine;
use reqwest::StatusCode;
use serde::Deserialize;

use crate::models::HarborRepo;

#[derive(Clone)]
pub struct HarborClient {
    base_url: String,
    project: String,
    client: reqwest::Client,
}

impl HarborClient {
    pub fn new(
        base_url: String,
        project: String,
        username: Option<String>,
        password: Option<String>,
    ) -> anyhow::Result<Self> {
        let mut headers = reqwest::header::HeaderMap::new();
        headers.insert(
            reqwest::header::ACCEPT,
            reqwest::header::HeaderValue::from_static("application/json"),
        );

        if let (Some(u), Some(p)) = (username.as_ref(), password.as_ref()) {
            let token = base64::engine::general_purpose::STANDARD.encode(format!("{u}:{p}"));
            let v = reqwest::header::HeaderValue::from_str(&format!("Basic {token}"))?;
            headers.insert(reqwest::header::AUTHORIZATION, v);
        }

        let client = reqwest::Client::builder()
            .default_headers(headers)
            .build()?;

        Ok(Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            project,
            client,
        })
    }

    fn url(&self, path: &str) -> String {
        format!("{}{}", self.base_url, path)
    }

    pub async fn list_latest_apps(&self) -> anyhow::Result<Vec<HarborRepo>> {
        let repos = self.list_repositories().await?;
        let mut apps = Vec::new();

        for repo in repos {
            match self.list_artifacts(&repo).await {
                Ok(arts) => {
                    if let Some(app) = resolve_latest_from_artifacts(&repo, &arts) {
                        apps.push(app);
                    }
                }
                Err(_) => {
                    continue;
                }
            }
        }

        apps.sort_by(|a, b| a.repo.cmp(&b.repo));
        Ok(apps)
    }

    async fn list_repositories(&self) -> anyhow::Result<Vec<String>> {
        #[derive(Debug, Deserialize)]
        struct RepoItem {
            name: Option<String>,
        }

        let mut repos = Vec::new();
        let mut page = 1;
        let page_size = 100;

        loop {
            let url = self.url(&format!("/api/v2.0/projects/{}/repositories", self.project));
            let resp = self
                .client
                .get(url)
                .query(&[("page", page), ("page_size", page_size)])
                .timeout(std::time::Duration::from_secs(15))
                .send()
                .await?;

            if !resp.status().is_success() {
                anyhow::bail!("Harbor repositories request failed: {}", resp.status());
            }

            let data: Vec<RepoItem> = resp.json().await?;
            for item in &data {
                if let Some(name) = &item.name {
                    repos.push(name.clone());
                }
            }

            if data.len() < page_size as usize {
                break;
            }
            page += 1;
        }

        Ok(repos)
    }

    async fn list_artifacts(&self, repository: &str) -> anyhow::Result<Vec<Artifact>> {
        let repo_short = repository
            .strip_prefix(&format!("{}/", self.project))
            .unwrap_or(repository);

        let mut artifacts = Vec::new();
        let mut page = 1;
        let page_size = 100;

        loop {
            let url = self.url(&format!(
                "/api/v2.0/projects/{}/repositories/{}/artifacts",
                self.project, repo_short
            ));

            let resp = self
                .client
                .get(url)
                .query(&[
                    ("page", page.to_string()),
                    ("page_size", page_size.to_string()),
                    ("with_tag", "true".to_string()),
                ])
                .timeout(std::time::Duration::from_secs(15))
                .send()
                .await?;

            if resp.status() == StatusCode::FORBIDDEN || resp.status() == StatusCode::UNAUTHORIZED {
                anyhow::bail!("Harbor artifacts request forbidden");
            }
            if !resp.status().is_success() {
                anyhow::bail!("Harbor artifacts request failed: {}", resp.status());
            }

            let data: Vec<Artifact> = resp.json().await.context("decode artifacts")?;
            artifacts.extend(data.iter().cloned());

            if data.len() < page_size as usize {
                break;
            }
            page += 1;
        }

        Ok(artifacts)
    }
}

#[derive(Clone, Debug, Deserialize)]
struct Artifact {
    tags: Option<Vec<Tag>>,
}

#[derive(Clone, Debug, Deserialize)]
struct Tag {
    name: Option<String>,
}

fn resolve_latest_from_artifacts(repo: &str, artifacts: &[Artifact]) -> Option<HarborRepo> {
    for art in artifacts {
        let tags = art.tags.as_ref()?;
        let mut tag_names: Vec<String> = tags.iter().filter_map(|t| t.name.clone()).collect();

        if !tag_names.iter().any(|t| t == "latest") {
            continue;
        }

        let resolved = resolve_tag(&tag_names);
        tag_names.sort();

        return Some(HarborRepo {
            repo: repo.to_string(),
            tag: resolved,
            all_tags: tag_names,
        });
    }

    None
}

pub fn resolve_tag(tag_names: &[String]) -> String {
    let numeric = tag_names
        .iter()
        .find(|t| t.chars().any(|c| c.is_ascii_digit()));
    if let Some(t) = numeric {
        return t.clone();
    }

    let non_latest = tag_names.iter().find(|t| t.as_str() != "latest");
    if let Some(t) = non_latest {
        return t.clone();
    }

    "latest".to_string()
}
