use hello_world::{greeter_client::GreeterClient, HelloRequest};
use opentelemetry::{
    global,
    propagation::Injector,
    sdk::{propagation::TraceContextPropagator, trace, Resource},
};
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_semantic_conventions as semcov;
use tracing::*;
use tracing_futures::Instrument;
use tracing_opentelemetry::OpenTelemetrySpanExt;
use tracing_subscriber::prelude::*;

struct MetadataMap<'a>(&'a mut tonic::metadata::MetadataMap);

impl<'a> Injector for MetadataMap<'a> {
    /// Set a key and value in the MetadataMap.  Does nothing if the key or value are not valid inputs
    fn set(&mut self, key: &str, value: String) {
        if let Ok(key) = tonic::metadata::MetadataKey::from_bytes(key.as_bytes()) {
            if let Ok(val) = tonic::metadata::MetadataValue::from_str(&value) {
                self.0.insert(key, val);
            }
        }
    }
}

pub mod hello_world {
    tonic::include_proto!("helloworld");
}

#[instrument]
async fn greet() -> Result<(), Box<dyn std::error::Error + Send + Sync + 'static>> {
    let mut client = GreeterClient::connect("http://[::1]:50051")
        .instrument(info_span!("client connect"))
        .await?;

    let mut request = tonic::Request::new(HelloRequest {
        name: "Tonic".into(),
    });

    global::get_text_map_propagator(|propagator| {
        propagator.inject_context(
            &tracing::Span::current().context(),
            &mut MetadataMap(request.metadata_mut()),
        )
    });

    let response = client
        .say_hello(request)
        .instrument(info_span!("say_hello"))
        .await?;

    info!("Response received: {:?}", response);
    Ok(())
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync + 'static>> {
    global::set_text_map_propagator(TraceContextPropagator::new());

    let tracer = opentelemetry_otlp::new_pipeline()
        .tracing()
        .with_trace_config(trace::config().with_resource(Resource::new(vec![
            semcov::resource::SERVICE_NAME.string("grpc-client"),
            semcov::resource::SERVICE_VERSION.string("0.1.0"),
        ])))
        .with_exporter(
            opentelemetry_otlp::new_exporter()
                .tonic()
                .with_endpoint("http://localhost:4317"),
        )
        .install_batch(opentelemetry::runtime::Tokio)?;
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::new("INFO"))
        .with(tracing_opentelemetry::layer().with_tracer(tracer))
        .try_init()?;

    greet().await?;

    opentelemetry::global::shutdown_tracer_provider();

    Ok(())
}
