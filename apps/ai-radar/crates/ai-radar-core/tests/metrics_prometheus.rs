use ai_radar_core::domain::SourceType;
use ai_radar_core::metrics::{describe_metrics, record_collect_pass, record_extract_pass, record_score_pass};
use metrics_exporter_prometheus::PrometheusBuilder;

#[test]
fn prometheus_metrics_increment_for_pipeline_helpers() {
    // Install a recorder for this test only.
    let handle = PrometheusBuilder::new()
        .install_recorder()
        .expect("install recorder");

    describe_metrics();

    record_collect_pass(
        SourceType::Rss,
        3,  // collected
        2,  // skipped
        1,  // source_errors
        4,  // skipped_poll
        std::time::Duration::from_millis(1200),
    );
    record_extract_pass(5, 1, std::time::Duration::from_millis(900));
    record_score_pass(7, 0, std::time::Duration::from_millis(450));

    let rendered = handle.render();

    assert!(
        rendered.contains("ai_radar_collected_total{source_type=\"rss\"} 3"),
        "expected collected counter: {rendered}"
    );
    assert!(
        rendered.contains("ai_radar_skipped_total{source_type=\"rss\"} 2"),
        "expected skipped counter: {rendered}"
    );
    assert!(
        rendered.contains("ai_radar_errors_total{stage=\"collect\"} 1"),
        "expected errors_total collect: {rendered}"
    );
    assert!(
        rendered.contains("ai_radar_sources_skipped_poll_total{source_type=\"rss\"} 4"),
        "expected skipped_poll counter: {rendered}"
    );

    assert!(
        rendered.contains("ai_radar_extracted_total 5"),
        "expected extracted counter: {rendered}"
    );
    assert!(
        rendered.contains("ai_radar_extract_failed_total 1"),
        "expected extract failed counter: {rendered}"
    );

    assert!(
        rendered.contains("ai_radar_scored_total 7"),
        "expected scored counter: {rendered}"
    );
}

