using System;
using System.ComponentModel.DataAnnotations;

namespace jVision.Shared.Models
{
    public class ScratchPage
    {
        public int ScratchPageId { get; set; }

        [Required]
        public string Title { get; set; }

        // Verbatim text -- payloads, hashes, one-liners. Never trimmed or
        // reformatted; whitespace is often load-bearing in a payload.
        public string Content { get; set; }

        // Stamped server-side from the authenticated user on every save.
        public string UpdatedBy { get; set; }

        public DateTime UpdatedAt { get; set; }
    }
}
