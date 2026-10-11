using System;
using System.ComponentModel.DataAnnotations;

namespace jVision.Shared.Models
{
    public class LogEntry
    {
        public int LogEntryId { get; set; }

        // Timestamp parsed from the log line itself (both zsh and burp emit
        // "YYYY-MM-DD HH:MM:SS" prefixes), UTC. Falls back to server receive
        // time if the sync client couldn't parse it.
        public DateTime Timestamp { get; set; }

        // jVision username of the operator whose box produced the line.
        // NOT [Required] here: the server authoritatively overwrites this with
        // User.Identity.Name after model binding, so requiring it up front just
        // 400s every legitimate push. DB-level NOT NULL is kept in the migration.
        public string Operator { get; set; }

        // "zsh" or "burp".
        [Required]
        public string Source { get; set; }

        // Raw log line, including the leading timestamp. Kept verbatim so
        // report writers can quote it as-is (attribution artifact).
        [Required]
        public string Line { get; set; }
    }
}
