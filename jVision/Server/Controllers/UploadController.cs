using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net.Http.Headers;
using System.Threading.Tasks;
using jVision.Server.Data;
using jVision.Server.Hubs;
using jVision.Shared.Models;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Http.Extensions;

namespace jVision.Server.Controllers
{
    [Route("[controller]")]
    [ApiController]
    public class UploadController : ControllerBase
    {
        private readonly JvisionServerDBContext _context;
        private readonly IHubContext<BoxHub, IBoxClient> _hubContext;
        private readonly IWebHostEnvironment _hostEnvironment;
        //HUB CONTEXt
        public UploadController(JvisionServerDBContext context, IHubContext<BoxHub, IBoxClient> hubContext, IWebHostEnvironment environment)
        {
            _context = context;
            _hubContext = hubContext;
            _hostEnvironment = environment;
        }


        [HttpGet]
        public async Task<ActionResult<IEnumerable<AquaUpload>>> GetAqua()
        {
            return await _context.AquaUpload.ToListAsync();
        }

        [HttpPost]
        [DisableRequestSizeLimit]
        public async Task<IActionResult> Upload()
        {
            try
            {
                var formCollection = await Request.ReadFormAsync();
                var file = formCollection.Files.First();
                    
                var pathToSave = Path.Combine(Directory.GetCurrentDirectory(), "Aquastatic");
                if (file.Length > 0)
                {

                    var fileContent = ContentDispositionHeaderValue.Parse(file.ContentDisposition);
                    var fileName = ContentDispositionHeaderValue.Parse(file.ContentDisposition).FileName.Trim('"');
                    string myGuid = Guid.NewGuid().ToString();
                    var newPath = Path.Combine(pathToSave, myGuid);
                    if(Path.GetExtension(fileName).ToUpper() == ".ZIP")
                    {
                        Directory.CreateDirectory(newPath);

                        var fullPath = Path.Combine(newPath, fileName);
                        using (var stream = new FileStream(fullPath, FileMode.Create))
                        {
                            await file.CopyToAsync(stream);

                        }
                        ZipFile.ExtractToDirectory(fullPath, newPath);
                        //string urlPath = Path.Combine(_hostEnvironment.WebRootPath, myGuid);
                        //string requestPath = UriHelper.GetDisplayUrl(this.HttpContext.Request);
                        string basePath = GetBaseUrl();
                        string requestPath = $"{basePath}/Aquastatic/{myGuid}/aquatone_report.html";
                        try
                        {
                            AquaUpload aq = new AquaUpload
                            {
                                FileName = fileName,
                                Url = requestPath
                            };

                            await _context.AddAsync(aq);
                            await _context.SaveChangesAsync();
                            await _hubContext.Clients.All.AquaAdded(aq);
                        } catch
                        {
                            return StatusCode(500);
                        }

                        return StatusCode(200);
                    } else
                        {
                        return BadRequest();
                    }
                    //var dbPath = Path.Combine(folderName, fileName);

                    //return Ok(dbPath);
                    
                }
                else
                {
                    return BadRequest();
                }
            }
            catch (Exception ex)
            {
                return StatusCode(500, $"Internal server error: {ex}");
            }
        }

        private string GetBaseUrl()
        {
            var request = this.Request;
            var host = request.Host.ToUriComponent();
            //var pathBase = request.PathBase.ToUriComponent();
            return $"{request.Scheme}://{host}";
        }
    }
}
