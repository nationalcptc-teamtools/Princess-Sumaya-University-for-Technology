using Microsoft.EntityFrameworkCore.Migrations;

namespace jVision.Server.Migrations
{
    public partial class standing : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Active",
                table: "Boxes");

            migrationBuilder.DropColumn(
                name: "Comeback",
                table: "Boxes");

            migrationBuilder.DropColumn(
                name: "Pwned",
                table: "Boxes");

            migrationBuilder.DropColumn(
                name: "Unrelated",
                table: "Boxes");

            migrationBuilder.AddColumn<string>(
                name: "Standing",
                table: "Boxes",
                type: "TEXT",
                nullable: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Standing",
                table: "Boxes");

            migrationBuilder.AddColumn<bool>(
                name: "Active",
                table: "Boxes",
                type: "INTEGER",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "Comeback",
                table: "Boxes",
                type: "INTEGER",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "Pwned",
                table: "Boxes",
                type: "INTEGER",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "Unrelated",
                table: "Boxes",
                type: "INTEGER",
                nullable: false,
                defaultValue: false);
        }
    }
}
