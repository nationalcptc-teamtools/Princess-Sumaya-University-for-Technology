using Microsoft.EntityFrameworkCore.Migrations;

namespace jVision.Server.Migrations
{
    public partial class adduploadedscanhosts : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "UploadedScanHost",
                columns: table => new
                {
                    UploadedScanHostId = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    ScanUploadId = table.Column<int>(type: "INTEGER", nullable: false),
                    Ip = table.Column<string>(type: "TEXT", nullable: true),
                    Hostname = table.Column<string>(type: "TEXT", nullable: true),
                    ServicesJson = table.Column<string>(type: "TEXT", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_UploadedScanHost", x => x.UploadedScanHostId);
                });

            migrationBuilder.CreateIndex(
                name: "IX_UploadedScanHost_Ip",
                table: "UploadedScanHost",
                column: "Ip");

            migrationBuilder.CreateIndex(
                name: "IX_UploadedScanHost_ScanUploadId",
                table: "UploadedScanHost",
                column: "ScanUploadId");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(name: "UploadedScanHost");
        }
    }
}
