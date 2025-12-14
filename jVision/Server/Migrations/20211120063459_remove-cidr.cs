using Microsoft.EntityFrameworkCore.Migrations;

namespace jVision.Server.Migrations
{
    public partial class removecidr : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Cidr",
                table: "Boxes");

            migrationBuilder.AlterColumn<string>(
                name: "Ip",
                table: "Boxes",
                type: "TEXT",
                nullable: false,
                defaultValue: "",
                oldClrType: typeof(string),
                oldType: "TEXT",
                oldNullable: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<string>(
                name: "Ip",
                table: "Boxes",
                type: "TEXT",
                nullable: true,
                oldClrType: typeof(string),
                oldType: "TEXT");

            migrationBuilder.AddColumn<string>(
                name: "Cidr",
                table: "Boxes",
                type: "TEXT",
                nullable: true);
        }
    }
}
