use std::{net::SocketAddr, path::PathBuf, sync::Arc};

use ap_python_launcher::{
    config::Config,
    http::{prefix::StripApPythonPrefixLayer, routes, static_files::StaticFilesService},
};
use axum::Router;
use tower::ServiceBuilder;
use tower_http::trace::TraceLayer;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    let cfg = Arc::new(Config::from_env()?);

    let api = routes::router(routes::AppState { cfg: cfg.clone() });

    let static_dir = PathBuf::from("./static");
    let static_svc = StaticFilesService::new(static_dir);

    let app = Router::new().merge(api).fallback_service(static_svc).layer(
        ServiceBuilder::new()
            .layer(TraceLayer::new_for_http())
            .layer(StripApPythonPrefixLayer),
    );

    let addr = SocketAddr::from(([0, 0, 0, 0], cfg.port));
    tracing::info!(%addr, "listening");

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
