using Microsoft.EntityFrameworkCore.Migrations;

namespace jVision.Server.Migrations
{
    // Adds Box.Domain — free-text AD/DNS domain for a host, shown as a chip
    // under each host card on the network topology.
    public partial class addboxdomain : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Domain",
                table: "Boxes",
                type: "TEXT",
                nullable: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(name: "Domain", table: "Boxes");
        }
    }
}
