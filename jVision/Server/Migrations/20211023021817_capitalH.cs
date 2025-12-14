using Microsoft.EntityFrameworkCore.Migrations;

namespace jVision.Server.Migrations
{
    public partial class capitalH : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.RenameColumn(
                name: "hostname",
                table: "Boxes",
                newName: "Hostname");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.RenameColumn(
                name: "Hostname",
                table: "Boxes",
                newName: "hostname");
        }
    }
}
