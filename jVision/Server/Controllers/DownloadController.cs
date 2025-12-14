using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using jVision.Server.Download;
using jVision.Server.Data;
using Microsoft.EntityFrameworkCore;
using jVision.Server.Models;
using Newtonsoft.Json;

namespace jVision.Server.Controllers
{
    [Route("[controller]")]
    [ApiController]
    public class DownloadController : ControllerBase
    {
        private readonly JvisionServerDBContext _context;
        public DownloadController(JvisionServerDBContext context)
        {
            _context = context;
        }
        [HttpGet("{file}")]
        public async Task<IActionResult> DownloadDiagram(string file)
        {
            var Boxes = _context.Boxes.Include(i => i.Services).ToList();
            switch(file)
            {
                case "diagram":
                    //return StatusCode(400);
                    return CreateDiagram(Boxes.OrderBy(i=>Version.Parse(i.Ip)).ToList());
                case "topology":
                    return CreateTopology(Boxes.OrderBy(i=>Version.Parse(i.Ip)).ToList());
                default:
                    return StatusCode(500);
            }
            return StatusCode(500);

        }

        private FileResult CreateTopology(List<Box> bl)
        {
            var subnets = bl.Select(i => i.Subnet).Distinct().ToList();
            var myExport = new CsvExport();
            var styles = new Dictionary<string, string>()
            {
                {"atkr","fontColor=#232F3E;fillColor=#232F3E;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;shape=image;image=data:image/png,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;strokeColor=#232F3E;aspect=fixed;whiteSpace=wrap;" },
                {"rtr","fontColor=#232F3E;fillColor=#232F3E;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;shape=image;image=img/lib/clip_art/networking/Router_Icon_128x128.png;strokeColor=#232F3E;aspect=fixed;whiteSpace=wrap;" },
                {"default","verticalLabelPosition=bottom;html=1;verticalAlign=top;align=center;strokeColor=none;fillColor=#00BEF2;shape=mxgraph.azure.computer;pointerEvents=1;" },
                {"sunet", "swimlane;html=1;fontStyle=1;startSize=60;strokeColor=#3F7DE0;fillColor=#3f7de0;collapsible=0;fontColor=#ffffff;fontSize=18;whiteSpace=wrap;html=1;" },
                {"rekt","shape=rectangle;fillColor=#3F7DE0;strokeColor=#3F7DE0;fontSize=14;fontColor=#FFFFFF;aspect=fixed;align=center;whiteSpace=wrap;html=1" },
                {"Windows","image;sketch=0;aspect=fixed;html=1;points=[];align=center;fontSize=12;image=img/lib/mscae/VirtualMachineWindows.svg;" },
                {"Linux","image;sketch=0;aspect=fixed;html=1;points=[];align=center;fontSize=12;image=img/lib/mscae/VM_Linux.svg;" }
            };
            List<string> config = new List<string>
            {
               "label: %name%",
               "parentstyle: swimlane; autoSize=1;fontStyle=1;fontColor=#FFFFFF;childLayout=flowLayout;horizontal=1;startSize=35;fillColor=#3f7de0;horizontalStack=1;resizeParent=0;resizeChildren=0;collapsible=0; align=center; verticalAlign=top; recursiveResize=0; container=1;fontSize=12;whiteSpace=wrap;html=1;",
               "stylename: cat",
               $"styles: {JsonConvert.SerializeObject(styles)}",
               "vars: -",
               "labelname: -",
               "labels: -",
               "identity: identity",
               "parent: parent",
               "namespace: csvimport-",
               "connect:{\"from\": \"refs\", \"to\":\"id\", \"style\":\"rounded=0; endArrow = classic; jumpStyle = sharp; strokeColor =#3f7de0\"}",
               "left: ",
               "top: ",
               "width: @width",
               "height: @height",
               "padding: 15",
               "ignore: id, cat, fill, refs",
               "nodespacing: 40",
               "levelspacing: 100",
               "edgespacing: 40",
               "layout: verticaltree"
            };
            myExport.AddContent(config);
            var attacker_parent = new List<Topology>
            {
                new Topology{id="attacker_parent",name="Attacker Network", refs="router",cat="sunet",width="180",height="200",parent="",identity="attacker_parent" }
            };
            myExport.AddRows(attacker_parent);
            var attacker_record = new List<Topology>
            {
                new Topology{id="attacker",name="VDI Infrastructure",refs="",cat="atkr",width="80",height="76",parent="",identity="attacker"}
            };
            myExport.AddRows(attacker_record);

            var router_record = new List<Topology>
            {
                new Topology{id="router",name="",refs=String.Join(",",subnets),cat="rtr",height="56",width="122",parent="",identity="router"}
            };
            myExport.AddRows(router_record);
            foreach (var subnet in subnets)
            {
                var subnet_boxes = bl.Where(s => s.Subnet.Equals(subnet)).ToList();
                var subnet_parent = new List<Topology>
                {
                    new Topology{id=subnet,name=$"CHANGE ME<br>{subnet}",refs="",cat="sunet",width="580",height="360",parent="",identity=subnet}
                };
                myExport.AddRows(subnet_parent);
                foreach(var box in subnet_boxes)
                {
                    var os = string.IsNullOrEmpty(box.Os) ? "default" : box.Os;
                    var comp_record = new List<Topology>
                    {
                        new Topology{id=$"subnet{box.Ip}", name=$"{box.Hostname}<br>{box.Ip}",refs="",cat=os,width="82",height="72",parent="",identity=$"subnet{box.Ip}"}
                    };
                    myExport.AddRows(comp_record);
                }
            }
            
            return File(myExport.ExportToBytes(), "text/csv", "topology.csv");
        }

        private FileResult CreateDiagram(List<Box> bl)
        {
            var myExport = new CsvExport();

            List<string> config = new List<string>
            {
                "label: %component%",
                "style: shape=%shape%;fillColor=%fill%;strokeColor=%stroke%;fontSize=%fontSize%;fontColor=%font%;aspect=fixed;%type%;image=%image%;align=center;whiteSpace=wrap;html=1",
                "namespace: csvimport-",
                "connect: {\"from\":\"refs\", \"to\":\"id\",\"style\":\"opacity=0\",\"invert\":true}",
                "width: @width",
                "parentstyle: swimlane;fontStyle=1;childLayout=stackLayout;horizontal=1;startSize=46;fillColor=#3f7de0;horizontalStack=0;resizeParent=1;resizeParentMax=0;resizeLast=0;collapsible=1;fontColor=#ffffff;aspect=fixed;fontSize=14;whiteSpace=wrap;html=1",
                "parent: parent",
                "identity: identity",
                "height: @height",
                "left:%left%",
                "padding: 15",
                "ignore: id, shape, fill, stroke, refs",
                "nodespacing: 40",
                "levelspacing: 20",
                "edgespacing: 40",
                "layout: horizontalflow"
            };
            myExport.AddContent(config);

            var subnets = bl.Select(i => i.Subnet).Distinct().ToList();
            foreach (var subnet in subnets)
            {
                var subnet_boxes = bl.Where(s => s.Subnet.Equals(subnet)).ToList();
                
                var windows_boxes = bl.Where(s => s.Subnet.Equals(subnet) && s.Os != null && String.Equals(s.Os, "Windows", StringComparison.OrdinalIgnoreCase));
                var linux_boxes = bl.Where(s => s.Subnet.Equals(subnet) && s.Os != null && String.Equals(s.Os, "Linux", StringComparison.OrdinalIgnoreCase));
                var other_boxes = bl.Where(s => s.Subnet.Equals(subnet) && s.Os != null && (!String.Equals(s.Os, "Windows", StringComparison.OrdinalIgnoreCase) && !String.Equals(s.Os, "Linux", StringComparison.OrdinalIgnoreCase)));
                var subnet_record = new List<Diagram>
                {
                    new Diagram{id=$"subnet{subnet}", component=subnet, refs="", fill="#3f7de0",stroke="",shape="rectangle",type="",image="",font="#FFFFFF", fontSize="14", parent="",height="40", width="200",identity=$"subnet{subnet}"}
                };
                myExport.AddRows(subnet_record);

                foreach (var box in subnet_boxes)
                {
                    string message = "";
                    foreach (var s in box.Services.Where(s => String.Equals(s.State, "open", StringComparison.OrdinalIgnoreCase)).ToList())
                    {
                        message += "Port " + s.Port.ToString() + " - " + (s.Name ?? "") + "<br>";
                    }
                    var info_record = new List<Diagram>
                    {
                        new Diagram{id=$"info{box.BoxId}",component=(box.Ip + "<br>" + box.Hostname),refs=$"box{box.BoxId}",fill="#3f7de0",stroke="",shape="",type="swimlane",image="",width="220",height="80",font="#FFFFFF",fontSize="14",parent="", identity=$"info{box.BoxId}"}
                    };
                    var text_record = new List<Diagram>
                    {
                        new Diagram{id=$"text{box.BoxId}",component=message,refs="",fill="",stroke="",shape="",type="text",image="",width="220",height="80",font="#000000", fontSize="14",parent=$"info{box.BoxId}", identity=$"text{box.BoxId}"}
                    };

                        myExport.AddRows(info_record);
                        myExport.AddRows(text_record);
                }


                foreach (var box in windows_boxes)
                {
                    var image_record = new List<Diagram>
                {
                    new Diagram{id=$"box{box.BoxId}", component="",refs="",fill="",stroke="",shape="",type="image",image="img/lib/mscae/VirtualMachineWindows.svg",width="90",height="80",font="",fontSize="",parent="",identity=$"box{box.BoxId}"}
                };
                    myExport.AddRows(image_record);
                }
                foreach (var box in linux_boxes)
                {
                    var image_record = new List<Diagram>
                {
                    new Diagram{id=$"box{box.BoxId}", component="",refs="",fill="",stroke="",shape="",type="image",image="img/lib/mscae/VM_Linux.svg",width="90",height="80",font="",fontSize="",parent="",identity=$"box{box.BoxId}"}
                };
                    myExport.AddRows(image_record);
                }
                foreach (var box in other_boxes)
                {
                    var image_record = new List<Diagram>
                {
                    new Diagram{id=$"box{box.BoxId}", component="",refs="",fill="",stroke="",shape="",type="image",image="",width="90",height="80",font="",fontSize="",parent="",identity=$"box{box.BoxId}"}
                };
                    myExport.AddRows(image_record);
                }
            }

            //List<string> header = new List<string> { "id", "component", "refs", "fill", "stroke", "shape", "type", "image", "width", "height", "font", "fontSize", "parent", "identity" };

           




            /**
            foreach (var box in windows_boxes)
            {
                var records = new List<Diagram>
                {
                    new Diagram{Id=$"box{box.BoxId}" }
                }
                myExport.AddRows(records);
            }
            **/
            return File(myExport.ExportToBytes(), "text/csv", "diagram.csv");
        }
    }
}
