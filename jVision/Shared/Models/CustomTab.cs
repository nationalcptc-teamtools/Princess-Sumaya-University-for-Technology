using System;
using System.ComponentModel.DataAnnotations;

namespace jVision.Shared.Models
{
    // Team-visible tab defined at runtime. Sits alongside the built-in tabs in
    // NavMenu; the body is shared free-text (payloads, hostnames, mini-runbooks)
    // that everyone on the team can read and edit.
    public class CustomTab
    {
        public int CustomTabId { get; set; }

        // Shown in the sidebar and used to derive the URL slug.
        [Required]
        public string Title { get; set; }

        // Open-iconic name (without the "oi-" prefix), e.g. "star", "flag".
        // Falls back to a generic icon on the client if empty.
        public string Icon { get; set; }

        // Free-form body -- can be markdown, notes, whatever. Not sanitized on
        // save; the client renders as plain text with newlines preserved.
        public string Content { get; set; }

        public string CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }
        public string UpdatedBy { get; set; }
        public DateTime UpdatedAt { get; set; }
    }
}
