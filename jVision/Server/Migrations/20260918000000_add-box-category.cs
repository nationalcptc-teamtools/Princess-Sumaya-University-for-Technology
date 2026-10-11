using Microsoft.EntityFrameworkCore.Migrations;

namespace jVision.Server.Migrations
{
    // Adds Box.Category — CPTC environment bucket (web / AD / OT / AI /
    // mobile / cloud) used by the network topology diagram to group hosts.
    public partial class addboxcategory : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Category",
                table: "Boxes",
                type: "TEXT",
                nullable: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(name: "Category", table: "Boxes");
        }
    }
}
