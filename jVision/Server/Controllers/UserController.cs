using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using jVision.Server.Data;
using jVision.Server.Models;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;

namespace jVision.Server.Controllers
{
    [Route("[controller]")]
    [ApiController]
    public class UserController : ControllerBase
    {
        private readonly JvisionServerDBContext _context;
        public UserController(JvisionServerDBContext context)
        {
            _context = context;
        }

        [HttpGet]
        public ActionResult<IEnumerable<string>> ListUsers()
        {
            return _context.Users.Select(u => u.UserName).ToList();
        }
    }
}
