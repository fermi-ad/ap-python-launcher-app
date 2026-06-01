use ap_python_launcher::harbor::resolve_tag;

#[test]
fn prefers_numeric_tag() {
    let tags = vec!["latest".to_string(), "v2".to_string(), "abc".to_string()];
    assert_eq!(resolve_tag(&tags), "v2");
}

#[test]
fn falls_back_to_first_non_latest() {
    let tags = vec!["latest".to_string(), "dev".to_string()];
    assert_eq!(resolve_tag(&tags), "dev");
}

#[test]
fn falls_back_to_latest() {
    let tags = vec!["latest".to_string()];
    assert_eq!(resolve_tag(&tags), "latest");
}
