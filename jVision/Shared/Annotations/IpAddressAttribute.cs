using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Text;
using System.Net;
using System.Threading.Tasks;
using System.Text.RegularExpressions;

namespace jVision.Shared.Annotations
{
    public class IpAddressAttribute : ValidationAttribute
    {
        private IPAddress iq;
        public string GetErrorMessage() => "This aint an Ip addresss dawg";

        protected override ValidationResult IsValid(object value, ValidationContext validationContext)
        {
            if (IPAddress.TryParse((string)value, out iq))
            {
                return ValidationResult.Success;
                
            } else
            {
                return new ValidationResult(GetErrorMessage());
            }
            
        }
    }
}
