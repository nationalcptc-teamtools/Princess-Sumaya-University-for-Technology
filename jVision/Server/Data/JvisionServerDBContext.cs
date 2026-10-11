using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using jVision.Server.Models;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using jVision.Shared.Models;

namespace jVision.Server.Data
{
    public class JvisionServerDBContext : IdentityDbContext<ApplicationUser>
    {
        public JvisionServerDBContext(DbContextOptions<JvisionServerDBContext> options) : base(options)
        {
        }
        public DbSet<JvisUser> JvisUsers { get; set; }

        public DbSet<Box> Boxes { get; set; }

        public DbSet<Cred> Cred { get; set; }

        public DbSet<LogEntry> LogEntry { get; set; }

        public DbSet<ScanUpload> ScanUpload { get; set; }

        public DbSet<UploadedScanHost> UploadedScanHost { get; set; }

        public DbSet<TeamIp> TeamIp { get; set; }

        public DbSet<ScratchPage> ScratchPage { get; set; }

        public DbSet<CustomTab> CustomTab { get; set; }

        public DbSet<CreatedAccount> CreatedAccount { get; set; }

        public DbSet<PivotEdge> PivotEdge { get; set; }

        public DbSet<CredUsage> CredUsage { get; set; }

        protected override void OnModelCreating(ModelBuilder builder)
        {
            base.OnModelCreating(builder);

            // One row per operator+address pair; the recorder relies on this to
            // upsert rather than pile up a row per request.
            builder.Entity<TeamIp>()
                .HasIndex(t => new { t.Operator, t.Ip })
                .IsUnique();

            // Speed up cred-usage lookups: "for this cred, where has it been
            // tried?" and "for this box, what creds have been tried here?"
            builder.Entity<CredUsage>().HasIndex(u => u.CredId);
            builder.Entity<CredUsage>().HasIndex(u => u.BoxId);

            // Pivot lookups by either endpoint.
            builder.Entity<PivotEdge>().HasIndex(p => p.SourceIp);
            builder.Entity<PivotEdge>().HasIndex(p => p.TargetIp);

            // Created accounts frequently listed per host.
            builder.Entity<CreatedAccount>().HasIndex(a => a.BoxId);
            builder.Entity<CreatedAccount>().HasIndex(a => a.Ip);
        }
    }
}
