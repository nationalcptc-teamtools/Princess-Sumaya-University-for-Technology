using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace jVision.Shared.Models
{
    public class ServiceDTO
    {
        public int ServiceId { get; set; }
        public int BoxId { get; set; }

        public int Port { get; set; }
        public string Protocol { get; set; }
        public string State { get; set; }
        public string Name { get; set; }

        public string Version { get; set; }
        public string Script { get; set; }
    }
}