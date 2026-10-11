using System;

namespace jVision.Shared.Models
{
    // Records where a Cred was actually tried and whether it worked. Powers
    // the "password tracker" view on Credies.razor — every cred can be
    // expanded to see the hosts/services it works on.
    public class CredUsage
    {
        public int CredUsageId { get; set; }

        public int CredId { get; set; }

        // Nullable so we can log usages against untracked hosts (still get
        // Ip in that case).
        public int? BoxId { get; set; }
        public string Ip { get; set; }

        public int? Port { get; set; }
        public string ServiceName { get; set; }

        // "valid" | "invalid" | "untested"
        public string Status { get; set; }
        public string Notes { get; set; }

        public string TestedBy { get; set; }
        public DateTime TestedAt { get; set; }
    }
}
