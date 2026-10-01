use std::collections::HashMap;
use xmltree::Element;
use xmltree::XMLNode;

#[derive(Debug, Clone)]
pub(crate) struct AnimInfo {
    pub(crate) attr_name: String,
    pub(crate) values: Vec<String>,
    pub(crate) key_times: Vec<f64>,
    pub(crate) dur: f64,
    pub(crate) calc_mode: CalcMode,
    pub(crate) transform_type: TransformType,
    pub(crate) from: Option<String>,
    pub(crate) to: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) enum CalcMode {
    Linear,
    Discrete,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) enum TransformType {
    None,
    Rotate,
}

pub(crate) fn extract_animations(doc: &Element) -> Vec<AnimInfo> {
    let mut anims = Vec::new();
    collect_animations(doc, &mut anims);
    anims
}

fn collect_animations(element: &Element, anims: &mut Vec<AnimInfo>) {
    for child in &element.children {
        if let XMLNode::Element(e) = child {
            let tag = &e.name;
            if tag == "animate" || tag == "animateTransform" {
                let attr_name = e
                    .attributes
                    .get("attributeName")
                    .map(|s| s.as_str())
                    .unwrap_or("")
                    .to_string();
                if attr_name.is_empty() {
                    continue;
                }
                let values = e
                    .attributes
                    .get("values")
                    .map(|v| v.split(';').map(|s| s.to_string()).collect())
                    .unwrap_or_default();
                let key_times = e
                    .attributes
                    .get("keyTimes")
                    .map(|v| v.split(';').filter_map(|s| s.parse().ok()).collect())
                    .unwrap_or_default();
                let dur_str = e.attributes.get("dur").map(|s| s.as_str()).unwrap_or("0s");
                let dur = parse_dur(dur_str);
                let calc_mode = match e
                    .attributes
                    .get("calcMode")
                    .map(|s| s.as_str())
                    .unwrap_or("linear")
                {
                    "discrete" => CalcMode::Discrete,
                    _ => CalcMode::Linear,
                };
                let transform_type = if tag == "animateTransform" {
                    match e.attributes.get("type").map(|s| s.as_str()).unwrap_or("") {
                        "rotate" => TransformType::Rotate,
                        _ => TransformType::None,
                    }
                } else {
                    TransformType::None
                };
                let from = e.attributes.get("from").map(|s| s.as_str().to_string());
                let to = e.attributes.get("to").map(|s| s.as_str().to_string());

                anims.push(AnimInfo {
                    attr_name,
                    values,
                    key_times,
                    dur,
                    calc_mode,
                    transform_type,
                    from,
                    to,
                });
            }
            collect_animations(e, anims);
        }
    }
}

pub(crate) fn parse_dur(s: &str) -> f64 {
    if s.ends_with("ms") {
        s.trim_end_matches("ms").parse().unwrap_or(0.0) / 1000.0
    } else if s.ends_with('s') {
        s.trim_end_matches('s').parse().unwrap_or(0.0)
    } else {
        s.parse().unwrap_or(0.0)
    }
}

pub(crate) fn bake_frame(doc: &Element, anims: &[AnimInfo], t: f64) -> String {
    let mut doc = doc.clone();
    apply_animations(&mut doc, anims, t);
    let mut buf = Vec::new();
    doc.write(&mut buf).expect("serialize");
    String::from_utf8(buf).expect("utf8")
}

fn apply_animations(element: &mut Element, anims: &[AnimInfo], t: f64) {
    let children: Vec<_> = element.children.iter_mut().collect();
    for child in children {
        if let XMLNode::Element(e) = child {
            apply_animations(e, anims, t);
        }
    }

    let mut my_anims: Vec<&AnimInfo> = Vec::new();
    for anim in anims {
        for child in &element.children {
            if let XMLNode::Element(e) = child {
                if e.name == "animate" || e.name == "animateTransform" {
                    let attr_name = e
                        .attributes
                        .get("attributeName")
                        .map(|s| s.as_str())
                        .unwrap_or("");
                    if attr_name == anim.attr_name {
                        my_anims.push(anim);
                    }
                }
            }
        }
    }

    if my_anims.is_empty() {
        return;
    }

    let mut final_values: HashMap<String, String> = HashMap::new();
    for anim in &my_anims {
        let t_mod = if anim.dur > 0.0 { t % anim.dur } else { 0.0 };
        let t_norm = if anim.dur > 0.0 {
            t_mod / anim.dur
        } else {
            0.0
        };
        let value = evaluate_animation(anim, t_norm);
        final_values.insert(anim.attr_name.clone(), value);
    }

    for (attr, value) in final_values {
        element.attributes.insert(attr, value);
    }

    element.children.retain(|child| {
        !matches!(child, XMLNode::Element(e) if e.name == "animate" || e.name == "animateTransform")
    });
}

fn evaluate_animation(anim: &AnimInfo, t_norm: f64) -> String {
    if anim.values.is_empty() {
        return anim.from.clone().unwrap_or_default();
    }

    match anim.calc_mode {
        CalcMode::Discrete => {
            for i in 1..anim.key_times.len() {
                if t_norm <= anim.key_times[i] {
                    return anim.values[i - 1].clone();
                }
            }
            anim.values.last().cloned().unwrap_or_default()
        }
        CalcMode::Linear => {
            for i in 1..anim.key_times.len() {
                if t_norm <= anim.key_times[i] {
                    let t0 = anim.key_times[i - 1];
                    let t1 = anim.key_times[i];
                    let v0 = anim.values[i - 1].parse::<f64>().unwrap_or(0.0);
                    let v1 = anim.values[i].parse::<f64>().unwrap_or(0.0);
                    if (t1 - t0).abs() < 1e-9 {
                        return format!("{:.3}", v0);
                    }
                    let frac = (t_norm - t0) / (t1 - t0);
                    let v = v0 + (v1 - v0) * frac;
                    return format!("{:.3}", v);
                }
            }
            anim.values.last().cloned().unwrap_or_default()
        }
    }
}

pub(crate) fn resolve_size(doc: &Element, width: Option<u32>, height: Option<u32>) -> (u32, u32) {
    let svg_width = doc.attributes.get("width").and_then(|v| v.parse().ok());
    let svg_height = doc.attributes.get("height").and_then(|v| v.parse().ok());
    let view_box = doc.attributes.get("viewBox").and_then(|v| {
        let parts: Vec<&str> = v.split_whitespace().collect();
        if parts.len() == 4 {
            let w: Option<u32> = parts[2].parse().ok();
            let h: Option<u32> = parts[3].parse().ok();
            w.zip(h)
        } else {
            None
        }
    });

    match (width, height, svg_width, svg_height, view_box) {
        (Some(w), Some(h), _, _, _) => (w, h),
        (None, None, Some(w), Some(h), _) => (w, h),
        (None, None, None, None, Some((_, h))) => (800, h),
        _ => (800, 600),
    }
}
