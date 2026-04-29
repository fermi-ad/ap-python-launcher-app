use ap_python_launcher::http::prefix::StripApPythonPrefixLayer;
use axum::{Router, body::Body, http::Request, response::Response, routing::get};
use tower::ServiceExt;

#[tokio::test]
async fn redirects_ap_python_to_trailing_slash() {
    let app = Router::new()
        .route("/", get(|| async { "ok" }))
        .layer(StripApPythonPrefixLayer);

    let res = app
        .oneshot(
            Request::builder()
                .uri("/ap-python")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(res.status(), 301);
    assert_eq!(res.headers().get("location").unwrap(), "/ap-python/");
}

#[tokio::test]
async fn strips_prefix_for_routing() {
    let app = Router::new()
        .route("/healthz", get(|| async { "ok" }))
        .layer(StripApPythonPrefixLayer)
        .route("/ap-python/healthz", get(|| async { "ok" }));

    let res: Response = app
        .oneshot(
            Request::builder()
                .uri("/ap-python/healthz")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(res.status(), 200);
}
