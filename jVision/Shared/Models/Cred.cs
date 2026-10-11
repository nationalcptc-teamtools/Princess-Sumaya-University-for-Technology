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
        // "obtained via SMB relay on 10.0.5.44" -- required in the report so
        // every cred gets a source annotation as it lands.
        public string Source { get; set; }
        // Flip true once we've actually used the cred to access something.
        public bool Verified { get; set; }
        // Where the cred came from: "Web", "AD" or "Others". Required on submit
        // and validated server-side. Nullable in the DB because rows added
        // before this field existed have no value.
        public string Origin { get; set; }
    }
}
