// Copyright 2021 System76 <info@system76.com>
// SPDX-FileCopyrightText: 2025 Alyssa Ross <hi@alyssa.is>
// SPDX-License-Identifier: MPL-2.0

// Adapted from freedesktop-desktop-entry 0.7.19.

use std::collections::BTreeMap;
use std::fmt::{self, Display, Formatter};

type Group = BTreeMap<String, String>;

#[derive(Debug)]
pub enum DecodeError {
    KeyValueWithoutAGroup,
    InvalidKey,
    InvalidValue,
}

impl Display for DecodeError {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        match self {
            Self::KeyValueWithoutAGroup => write!(f, "key/value without a group"),
            Self::InvalidKey => write!(f, "invalid key"),
            Self::InvalidValue => write!(f, "invalid value"),
        }
    }
}

pub fn parse(input: &str) -> Result<BTreeMap<String, Group>, DecodeError> {
    let mut groups = BTreeMap::default();
    let mut active_group: Option<ActiveGroup> = None;
    let mut active_keys: Option<ActiveKeys> = None;

    for line in input.lines() {
        process_line(line, &mut groups, &mut active_group, &mut active_keys)?;
    }

    if let Some(active_keys) = active_keys.take() {
        match &mut active_group {
            Some(active_group) => {
                active_group
                    .group
                    .insert(active_keys.key_name, active_keys.value);
            }
            None => return Err(DecodeError::KeyValueWithoutAGroup),
        }
    }

    if let Some(mut group) = active_group.take() {
        groups
            .entry(group.group_name)
            .or_default()
            .append(&mut group.group);
    }

    Ok(groups)
}

struct ActiveGroup {
    group_name: String,
    group: Group,
}

struct ActiveKeys {
    key_name: String,
    value: String,
}

#[inline(never)]
fn process_line(
    line: &str,
    groups: &mut BTreeMap<String, Group>,
    active_group: &mut Option<ActiveGroup>,
    active_keys: &mut Option<ActiveKeys>,
) -> Result<(), DecodeError> {
    if line.trim().is_empty() || line.starts_with('#') {
        return Ok(());
    }

    let line_bytes = line.as_bytes();

    // if group
    if line_bytes[0] == b'[' {
        if let Some(end) = line_bytes[1..].iter().rposition(|&b| b == b']') {
            let group_name = &line[1..end + 1];

            if let Some(active_keys) = active_keys.take() {
                match active_group {
                    Some(active_group) => {
                        active_group
                            .group
                            .insert(active_keys.key_name, active_keys.value);
                    }
                    None => return Err(DecodeError::KeyValueWithoutAGroup),
                }
            }

            if let Some(mut group) = active_group.take() {
                groups
                    .entry(group.group_name)
                    .or_default()
                    .append(&mut group.group);
            }

            active_group.replace(ActiveGroup {
                group_name: group_name.to_string(),
                group: Group::default(),
            });
        }
    }
    // else, if value
    else if let Some(delimiter) = line_bytes.iter().position(|&b| b == b'=') {
        let key = &line[..delimiter];
        let value = format_value(&line[delimiter + 1..])?;

        if key.is_empty() {
            return Err(DecodeError::InvalidKey);
        }

        if let Some(active_keys) = active_keys.take() {
            match active_group {
                Some(active_group) => {
                    active_group
                        .group
                        .insert(active_keys.key_name, active_keys.value);
                }
                None => return Err(DecodeError::KeyValueWithoutAGroup),
            }
        }
        active_keys.replace(ActiveKeys {
            key_name: key.trim().to_string(),
            value,
        });
    }
    Ok(())
}

// https://specifications.freedesktop.org/desktop-entry-spec/latest/value-types.html
#[inline]
fn format_value(input: &str) -> Result<String, DecodeError> {
    let input = if let Some(input) = input.strip_prefix(" ") {
        input
    } else {
        input
    };

    let mut res = String::with_capacity(input.len());

    let mut last: usize = 0;

    for (i, v) in input.as_bytes().iter().enumerate() {
        if *v != b'\\' {
            continue;
        }

        // edge case for //
        if last > i {
            continue;
        }

        // when there is an \ at the end
        if input.len() <= i + 1 {
            return Err(DecodeError::InvalidValue);
        }

        if last < i {
            res.push_str(&input[last..i]);
        }

        last = i + 2;

        match input.as_bytes()[i + 1] {
            b's' => res.push(' '),
            b'n' => res.push('\n'),
            b't' => res.push('\t'),
            b'r' => res.push('\r'),
            b'\\' => res.push('\\'),
            _ => {
                return Err(DecodeError::InvalidValue);
            }
        }
    }

    if last < input.len() {
        res.push_str(&input[last..input.len()]);
    }

    Ok(res)
}
