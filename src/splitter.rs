use crate::model::{SplitMode, SplitUnit};

pub fn split_text(
    content: &str,
    chunk_size: usize,
    unit: SplitUnit,
    split_mode: SplitMode,
) -> Vec<String> {
    if chunk_size == 0 {
        return vec![content.to_string()];
    }

    match unit {
        SplitUnit::Byte => split_byte_chunks(content, chunk_size, split_mode),
        SplitUnit::Word | SplitUnit::Token => split_word_chunks(content, chunk_size, unit),
    }
}

pub fn count_words(content: &str) -> usize {
    let mut count = 0usize;
    let mut in_word = false;
    for &b in content.as_bytes() {
        if b.is_ascii_whitespace() {
            in_word = false;
        } else if !in_word {
            count += 1;
            in_word = true;
        }
    }
    count
}

pub fn estimate_tokens(content: &str) -> usize {
    (count_words(content) * 4 + 2) / 3
}

fn split_byte_chunks(content: &str, chunk_size: usize, split_mode: SplitMode) -> Vec<String> {
    if split_mode == SplitMode::Exact {
        return content
            .as_bytes()
            .chunks(chunk_size)
            .map(|chunk| String::from_utf8_lossy(chunk).into_owned())
            .collect();
    }

    let mut chunks = Vec::new();
    let mut start = 0usize;
    let len = content.len();

    while start < len {
        let target_end = (start + chunk_size).min(len);
        let mut end = target_end;
        while end > start && !content.is_char_boundary(end) {
            end -= 1;
        }
        if end == start {
            end = next_char_boundary(content, target_end);
        }

        if split_mode == SplitMode::Line {
            if let Some(pos) = content.as_bytes()[start..end]
                .iter()
                .rposition(|&b| b == b'\n')
            {
                end = start + pos + 1;
            }
        } else if let Some(pos) = content.as_bytes()[start..end]
            .iter()
            .rposition(|&b| b.is_ascii_whitespace())
        {
            end = start + pos + 1;
        }

        chunks.push(content[start..end].to_string());
        start = end;
    }

    chunks
}

fn split_word_chunks(content: &str, chunk_size: usize, unit: SplitUnit) -> Vec<String> {
    let bytes = content.as_bytes();
    let mut chunks = Vec::new();
    let mut current_start = 0usize;
    let mut current_measure = 0usize;
    let mut i = 0usize;

    while i < bytes.len() {
        let word_start = i;
        while i < bytes.len() && !bytes[i].is_ascii_whitespace() {
            i += 1;
        }
        let word_end = i;
        while i < bytes.len() && bytes[i].is_ascii_whitespace() {
            i += 1;
        }

        let word_measure = match unit {
            SplitUnit::Byte => word_end - word_start,
            SplitUnit::Word => word_end - word_start,
            SplitUnit::Token => 1,
        };

        if word_measure > chunk_size {
            if current_measure > 0 {
                chunks.push(content[current_start..word_start].to_string());
            }
            chunks.push(content[word_start..word_end].to_string());
            current_start = i;
            current_measure = 0;
        } else if current_measure > 0 && current_measure + word_measure > chunk_size {
            chunks.push(content[current_start..word_start].to_string());
            current_start = word_start;
            current_measure = word_measure;
        } else {
            current_measure += word_measure;
        }
    }

    if current_start < content.len() {
        chunks.push(content[current_start..].to_string());
    }

    chunks
}

fn next_char_boundary(content: &str, mut idx: usize) -> usize {
    let len = content.len();
    if idx >= len {
        return len;
    }
    while idx < len && !content.is_char_boundary(idx) {
        idx += 1;
    }
    idx
}

pub fn apply_overlap(
    chunks: Vec<String>,
    overlap: usize,
    unit: SplitUnit,
    split_mode: SplitMode,
) -> Vec<String> {
    if overlap == 0 || chunks.len() <= 1 {
        return chunks;
    }

    let mut result = Vec::with_capacity(chunks.len());
    for (i, chunk) in chunks.iter().enumerate() {
        if i == 0 {
            result.push(chunk.clone());
        } else {
            let prev_tail = tail_by_unit(&chunks[i - 1], overlap, unit, split_mode);
            result.push(format!("{}{}", prev_tail, chunk));
        }
    }
    result
}

fn tail_by_unit(content: &str, amount: usize, unit: SplitUnit, split_mode: SplitMode) -> String {
    if amount == 0 || content.is_empty() {
        return String::new();
    }

    match unit {
        SplitUnit::Byte => {
            if amount >= content.len() {
                return content.to_string();
            }
            let mut end = content.len() - amount;
            while end > 0 && !content.is_char_boundary(end) {
                end -= 1;
            }
            if split_mode == SplitMode::Line {
                if let Some(pos) = content[..end].rfind('\n') {
                    return content[pos + 1..].to_string();
                }
            }
            content[end..].to_string()
        }
        SplitUnit::Word | SplitUnit::Token => {
            let mut words = 0usize;
            let mut start = content.len();
            let mut in_word = false;
            let mut word_start = content.len();

            for (idx, &b) in content.as_bytes().iter().enumerate().rev() {
                if b.is_ascii_whitespace() {
                    if in_word {
                        let next_words = words + 1;
                        if unit == SplitUnit::Token
                            && estimate_tokens_from_words(next_words) > amount
                        {
                            break;
                        }
                        words = next_words;
                        start = word_start;
                        if unit == SplitUnit::Word && words >= amount {
                            break;
                        }
                        in_word = false;
                    }
                } else if !in_word {
                    in_word = true;
                    word_start = idx;
                }
            }

            if in_word {
                let next_words = words + 1;
                if unit != SplitUnit::Token || estimate_tokens_from_words(next_words) <= amount {
                    words = next_words;
                    start = word_start;
                }
            }

            if words == 0 || amount >= words {
                content.to_string()
            } else {
                content[start..].to_string()
            }
        }
    }
}

fn estimate_tokens_from_words(words: usize) -> usize {
    (words * 4 + 2) / 3
}
