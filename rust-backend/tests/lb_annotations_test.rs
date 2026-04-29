use ap_python_launcher::kube_launcher::KubeLauncher;

#[test]
fn parses_lb_annotations_json_object() {
    let m = KubeLauncher::parse_lb_annotations_json(Some(r#"{"a":"b"}"#)).unwrap();
    assert_eq!(m.get("a").unwrap(), "b");
}
