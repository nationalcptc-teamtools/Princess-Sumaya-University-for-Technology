using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace jVision.Shared.Models
{
    public class Cred
    {
        public int CredId { get; set; }
        [Required]
        public string Text { get; set; }
        public string Type { get; set; }
    }
}
