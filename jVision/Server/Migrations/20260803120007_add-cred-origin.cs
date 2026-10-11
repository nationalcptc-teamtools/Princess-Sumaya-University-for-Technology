using Microsoft.EntityFrameworkCore.Migrations;

namespace jVision.Server.Migrations
{
    public partial class addcredorigin : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Nullable: creds captured before this column existed have no origin.
            migrationBuilder.AddColumn<string>(
                name: "Origin",
                table: "Cred",
                type: "TEXT",
                nullable: true);
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(name: "Origin", table: "Cred");
        }
    }
}
