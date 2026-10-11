using System;
using System.ComponentModel.DataAnnotations;

namespace jVision.Shared.Models
{
    // An account we created mid-engagement (e.g. a fresh SSH user on a
    // compromised box, a rogue domain user, a CMS admin we added). Auto-mirrors
    // to Cred so it also shows up on the Credentials tab; LinkedCredId is the
    // FK back to that mirror row so add/delete/update stay in sync.
    public class CreatedAccount
    {
        public int CreatedAccountId { get; set; }

        // Target box, if it's tracked. Nullable so we can log accounts on
        // hosts that aren't in the Boxes table yet.
        public int? BoxId { get; set; }

        // Denormalised IP so the row still makes sense if the Box row goes
        // away (or was never created).
        public string Ip { get; set; }

        // Freeform: "SSH", "AD", "WordPress admin", "MSSQL", ...
        public string Service { get; set; }

        [Required]
        public string Username { get; set; }

        public string Password { get; set; }

        // Freeform: "local user", "admin", "domain user", "domain admin", ...
        public string Privilege { get; set; }

        public string Notes { get; set; }

        public string CreatedBy { get; set; }
        public DateTime CreatedAt { get; set; }

        // FK to the auto-mirrored Cred row (Origin="Created").
        public int? LinkedCredId { get; set; }
    }
}
