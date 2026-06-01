use axum::{
    body::Body,
    http::{Request, StatusCode, Uri},
    response::Response,
};
use futures_util::future::BoxFuture;
use tower::{Layer, Service};

const URL_PREFIX: &str = "/ap-python";

#[derive(Clone, Debug, Default)]
pub struct StripApPythonPrefixLayer;

impl<S> Layer<S> for StripApPythonPrefixLayer {
    type Service = StripApPythonPrefixService<S>;

    fn layer(&self, inner: S) -> Self::Service {
        StripApPythonPrefixService { inner }
    }
}

#[derive(Clone, Debug)]
pub struct StripApPythonPrefixService<S> {
    inner: S,
}

impl<S, B> Service<Request<B>> for StripApPythonPrefixService<S>
where
    B: Send + 'static,
    S: Service<Request<B>, Response = Response> + Clone + Send + 'static,
    S::Future: Send + 'static,
    S::Error: Send + 'static,
{
    type Response = Response;
    type Error = S::Error;
    type Future = BoxFuture<'static, Result<Self::Response, Self::Error>>;

    fn poll_ready(
        &mut self,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, mut req: Request<B>) -> Self::Future {
        let path = req.uri().path().to_string();

        if path == URL_PREFIX {
            let mut parts = req.uri().clone().into_parts();
            parts.path_and_query = Some(format!("{URL_PREFIX}/").parse().unwrap());
            let uri = Uri::from_parts(parts).unwrap();

            let res = Response::builder()
                .status(StatusCode::MOVED_PERMANENTLY)
                .header("location", uri.to_string())
                .body(Body::empty())
                .unwrap();

            return Box::pin(async move { Ok(res) });
        }

        if path.starts_with(&format!("{URL_PREFIX}/")) {
            let stripped_path = &path[URL_PREFIX.len()..];
            let stripped_path = if stripped_path.is_empty() {
                "/"
            } else {
                stripped_path
            };

            if stripped_path == "/" {
                let res = Response::builder()
                    .status(StatusCode::MOVED_PERMANENTLY)
                    .header("location", format!("{URL_PREFIX}/"))
                    .body(Body::empty())
                    .unwrap();

                return Box::pin(async move { Ok(res) });
            }

            let mut parts = req.uri().clone().into_parts();
            let pq = match req.uri().query() {
                Some(q) => format!("{stripped_path}?{q}"),
                None => stripped_path.to_string(),
            };
            parts.path_and_query = Some(pq.parse().unwrap());
            *req.uri_mut() = Uri::from_parts(parts).unwrap();
        }

        let mut inner = self.inner.clone();
        Box::pin(async move { inner.call(req).await })
    }
}
