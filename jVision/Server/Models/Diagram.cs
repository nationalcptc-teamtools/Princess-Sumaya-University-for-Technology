namespace jVision.Server.Models
{
    public class Diagram
    {
        public string id { get; set; }
        public string component { get; set; }
        public string refs { get; set; }
        public string fill { get; set; }
        public string stroke { get; set; }
        public string shape { get; set; }
        public string type { get; set; }
        public string image { get; set; }
        public string width { get; set; }
        public string height { get; set; }
        public string font { get; set; }
        public string fontSize { get; set; }
        public string parent { get; set; }
        public string identity { get; set; }
    }
}
