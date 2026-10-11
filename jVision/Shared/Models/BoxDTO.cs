using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using jVision.Shared.Annotations;

namespace jVision.Shared.Models
{
    public class BoxDTO
    {
        public int BoxId { get; set; }
        public string UserId { get; set; }
        public string UserName { get; set; }
        [Required]
        [IpAddress]
        public string Ip { get; set; }
        public string Hostname { get; set; }
        public string State { get; set; }
        public string Comments { get; set; }

        public string Standing { get; set; }
        public string Os { get; set; }

        public string Subnet { get; set; }

        // AD/DNS domain the host belongs to (e.g. "corp.local"). Nullable.
        public string Domain { get; set; }

        // CPTC environment bucket (web / AD / OT / AI / mobile / cloud).
        // Groups hosts on the network topology diagram. Nullable.
        public string Category { get; set; }

        // Progress stage (todo/enum/foothold/privesc/owned). Null = untriaged.
        public string Stage { get; set; }

        public ICollection<ServiceDTO> Services { get; set; }

        // True if there's at least one UploadedScanHost row matching this IP,
        // so the Home row can decide whether to show the "Uploaded" button.
        public bool HasUploadedScans { get; set; }
    }
}
