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

        public ICollection<ServiceDTO> Services { get; set; }

    }
}
