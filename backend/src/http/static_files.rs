use std::path::{Path, PathBuf};

use axum::{
    body::Body,
    http::{Request, Response, StatusCode, Uri, header},
};
use tower::Service;

#[derive(Clone, Debug)]
pub struct StaticFilesService {
    root: PathBuf,
}

impl StaticFilesService {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    fn resolve_path(&self, uri: &Uri) -> PathBuf {
        let mut rel = uri.path().trim_start_matches('/').to_string();
        if rel.is_empty() {
            rel = "index.html".to_string();
        }
        if rel.ends_with('/') {
            rel.push_str("index.html");
        }

        let rel = rel.replace("..", "");
        self.root.join(rel)
    }

    async fn serve_file(path: &Path) -> Response<Body> {
        match tokio::fs::read(path).await {
            Ok(bytes) => {
                let mime = mime_guess::from_path(path).first_or_octet_stream();
                Response::builder()
                    .status(StatusCode::OK)
                    .header(header::CONTENT_TYPE, mime.as_ref())
                    .body(Body::from(bytes))
                    .unwrap()
            }
            Err(_) => Response::builder()
                .status(StatusCode::NOT_FOUND)
                .body(Body::empty())
                .unwrap(),
        }
    }
}

impl<B> Service<Request<B>> for StaticFilesService
where
    B: Send + 'static,
{
    type Response = Response<Body>;
    type Error = std::convert::Infallible;
    type Future = futures_util::future::BoxFuture<'static, Result<Self::Response, Self::Error>>;

    fn poll_ready(
        &mut self,
        _cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), Self::Error>> {
        std::task::Poll::Ready(Ok(()))
    }

    fn call(&mut self, req: Request<B>) -> Self::Future {
        let path = self.resolve_path(req.uri());
        Box::pin(async move { Ok(Self::serve_file(&path).await) })
    }
}
