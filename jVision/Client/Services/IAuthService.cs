using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using jVision.Shared.Models;

namespace jVision.Client.Services
{
    public interface IAuthService
    {
        Task Login(LoginRequest loginRequest);
        Task Register(RegisterRequest registerRequest);
        Task Logout();
        Task<CurrentUser> CurrentUserInfo();
    }
}
