using System;
using System.ComponentModel.DataAnnotations;

namespace jVision.Shared.Models
{
    public class ScanUpload
    {
        public int ScanUploadId { get; set; }
        [Required]
        public string FileName { get; set; }
        // NOT [Required]: server overrides with User.Identity.Name post-binding.
        public string Uploader { get; set; }
        public string Note { get; set; }
        public DateTime UploadedAt { get; set; }
        public long SizeBytes { get; set; }
        // Server-only: relative path on disk. Not populated for downloads-list
        // responses (there's no reason to leak the storage layout).
        public string StoredPath { get; set; }
    }
}
