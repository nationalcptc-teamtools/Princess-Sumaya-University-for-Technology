using System;
using System.Collections.Generic;

namespace jVision.Shared.Models
{
    // Per-host slice of an uploaded XML. Kept fully separate from Box.Services
    // by design -- the user wants the uploaded scan behind its own button on
    // the Home row (not mixed into the collapse-expand table).
    public class UploadedScanHost
    {
        public int UploadedScanHostId { get; set; }
        public int ScanUploadId { get; set; }
        public string Ip { get; set; }
        public string Hostname { get; set; }
        // Services serialized as JSON: List<ServiceDTO>. Trades relational
        // normalization for one fewer join / one fewer table.
        public string ServicesJson { get; set; }
    }

    // Response DTO for the Home-row popup. Rehydrates ServicesJson so the
    // client doesn't have to.
    public class UploadedScanView
    {
        public int ScanUploadId { get; set; }
        public string FileName { get; set; }
        public string Uploader { get; set; }
        public DateTime UploadedAt { get; set; }
        public string Note { get; set; }
        public string Ip { get; set; }
        public string Hostname { get; set; }
        public List<ServiceDTO> Services { get; set; }
    }
}
