using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace jVision.Shared.Models
{
    public class Upload
    {
        public bool Uploaded { get; set; }
        public string FileName { get; set; }
        public string StoredFileName { get; set; }
        public int ErrorCode { get; set; }
    }
}
