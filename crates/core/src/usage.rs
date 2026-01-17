//! Usage tracking with recency-weighted scoring

use anyhow::{Context, Result};
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

/// Half-life for recency weighting (7 days)
const HALF_LIFE_DAYS: i64 = 7;

/// A usage record for a single item
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UsageRecord {
    /// Path to the item
    pub path: String,
    /// Display name
    pub name: String,
    /// List of timestamps when the item was launched
    pub launches: Vec<DateTime<Utc>>,
}

impl UsageRecord {
    pub fn new(path: String, name: String) -> Self {
        Self {
            path,
            name,
            launches: vec![Utc::now()],
        }
    }

    /// Record a new launch
    pub fn record_launch(&mut self) {
        self.launches.push(Utc::now());
        // Keep only last 100 launches to prevent unbounded growth
        if self.launches.len() > 100 {
            self.launches.drain(0..self.launches.len() - 100);
        }
    }

    /// Calculate recency-weighted score
    /// Uses exponential decay with 7-day half-life
    pub fn score(&self) -> f64 {
        let now = Utc::now();
        let half_life = Duration::days(HALF_LIFE_DAYS);

        self.launches.iter().fold(0.0, |acc, &launch_time| {
            let age = now.signed_duration_since(launch_time);
            if age.num_seconds() < 0 {
                return acc + 1.0; // Future timestamps count as full weight
            }

            // Exponential decay: score = 2^(-age/half_life)
            let decay = (-age.num_seconds() as f64 / half_life.num_seconds() as f64).exp2();
            acc + decay
        })
    }
}

/// Usage data storage
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct UsageData {
    /// Program usage records keyed by path
    pub programs: HashMap<String, UsageRecord>,
    /// Document usage records keyed by path
    pub documents: HashMap<String, UsageRecord>,
    /// Last cleanup timestamp
    pub last_cleanup: Option<DateTime<Utc>>,
}

impl UsageData {
    /// Get the usage data file path
    pub fn data_path() -> Result<PathBuf> {
        let dirs = directories::ProjectDirs::from("com", "rmanov", "launcher")
            .context("Failed to determine data directory")?;
        let data_dir = dirs.data_dir();
        fs::create_dir_all(data_dir).context("Failed to create data directory")?;
        Ok(data_dir.join("usage.json"))
    }

    /// Load usage data from file
    pub fn load() -> Result<Self> {
        let path = Self::data_path()?;

        if path.exists() {
            let content = fs::read_to_string(&path)
                .with_context(|| format!("Failed to read usage data from {:?}", path))?;
            serde_json::from_str(&content)
                .with_context(|| format!("Failed to parse usage data from {:?}", path))
        } else {
            Ok(Self::default())
        }
    }

    /// Save usage data to file
    pub fn save(&self) -> Result<()> {
        let path = Self::data_path()?;
        let content = serde_json::to_string_pretty(self)?;
        fs::write(&path, content)
            .with_context(|| format!("Failed to write usage data to {:?}", path))?;
        Ok(())
    }

    /// Record a program launch
    pub fn record_program_launch(&mut self, path: &str, name: &str) {
        if let Some(record) = self.programs.get_mut(path) {
            record.record_launch();
        } else {
            self.programs.insert(
                path.to_string(),
                UsageRecord::new(path.to_string(), name.to_string()),
            );
        }
    }

    /// Record a document open
    pub fn record_document_open(&mut self, path: &str, name: &str) {
        if let Some(record) = self.documents.get_mut(path) {
            record.record_launch();
        } else {
            self.documents.insert(
                path.to_string(),
                UsageRecord::new(path.to_string(), name.to_string()),
            );
        }
    }

    /// Get top N programs by score
    pub fn top_programs(&self, n: usize) -> Vec<&UsageRecord> {
        let mut programs: Vec<_> = self.programs.values().collect();
        programs.sort_by(|a, b| b.score().partial_cmp(&a.score()).unwrap());
        programs.into_iter().take(n).collect()
    }

    /// Get top N documents by score
    pub fn top_documents(&self, n: usize) -> Vec<&UsageRecord> {
        let mut documents: Vec<_> = self.documents.values().collect();
        documents.sort_by(|a, b| b.score().partial_cmp(&a.score()).unwrap());
        documents.into_iter().take(n).collect()
    }

    /// Clean up old data (entries with score < 0.01)
    pub fn cleanup(&mut self) {
        let threshold = 0.01;

        self.programs.retain(|_, record| record.score() >= threshold);
        self.documents.retain(|_, record| record.score() >= threshold);

        self.last_cleanup = Some(Utc::now());
    }

    /// Perform daily cleanup if needed
    pub fn maybe_cleanup(&mut self) {
        let should_cleanup = match self.last_cleanup {
            Some(last) => {
                let elapsed = Utc::now().signed_duration_since(last);
                elapsed.num_hours() >= 24
            }
            None => true,
        };

        if should_cleanup {
            self.cleanup();
        }
    }
}

/// Usage tracker that auto-saves
pub struct UsageTracker {
    data: UsageData,
    dirty: bool,
}

impl UsageTracker {
    pub fn new() -> Result<Self> {
        let mut data = UsageData::load()?;
        data.maybe_cleanup();

        Ok(Self { data, dirty: false })
    }

    /// Record a program launch
    pub fn record_program(&mut self, path: &str, name: &str) {
        self.data.record_program_launch(path, name);
        self.dirty = true;
    }

    /// Record a document open
    pub fn record_document(&mut self, path: &str, name: &str) {
        self.data.record_document_open(path, name);
        self.dirty = true;
    }

    /// Get top programs
    pub fn top_programs(&self, n: usize) -> Vec<&UsageRecord> {
        self.data.top_programs(n)
    }

    /// Get top documents
    pub fn top_documents(&self, n: usize) -> Vec<&UsageRecord> {
        self.data.top_documents(n)
    }

    /// Save if there are unsaved changes
    pub fn save_if_dirty(&mut self) -> Result<()> {
        if self.dirty {
            self.data.save()?;
            self.dirty = false;
        }
        Ok(())
    }

    /// Force save
    pub fn save(&mut self) -> Result<()> {
        self.data.save()?;
        self.dirty = false;
        Ok(())
    }
}

impl Drop for UsageTracker {
    fn drop(&mut self) {
        let _ = self.save_if_dirty();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_usage_record_score() {
        let mut record = UsageRecord::new("/usr/bin/firefox".to_string(), "Firefox".to_string());

        // Fresh record should have score close to 1.0
        let score = record.score();
        assert!(score > 0.9 && score <= 1.0, "Fresh score: {}", score);

        // Adding more launches should increase score
        record.record_launch();
        record.record_launch();
        let new_score = record.score();
        assert!(new_score > score, "Score should increase with more launches");
    }

    #[test]
    fn test_top_programs() {
        let mut data = UsageData::default();

        // Add some programs
        data.record_program_launch("/usr/bin/firefox", "Firefox");
        data.record_program_launch("/usr/bin/firefox", "Firefox");
        data.record_program_launch("/usr/bin/code", "VS Code");

        let top = data.top_programs(2);
        assert_eq!(top.len(), 2);
        assert_eq!(top[0].name, "Firefox"); // Firefox has more launches
    }
}
