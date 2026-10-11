using System;
using Microsoft.EntityFrameworkCore.Migrations;

namespace jVision.Server.Migrations
{
    // Foundational schema for the multi-feature push:
    //   - Boxes.Stage       (per-box progress board)
    //   - CreatedAccount    (mid-engagement accounts tab)
    //   - PivotEdge         (attack-path arrows on topology)
    //   - CredUsage         (password tracker linked to Creds)
    public partial class multifeaturebaseline : Migration
    {
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Stage",
                table: "Boxes",
                type: "TEXT",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "CreatedAccount",
                columns: table => new
                {
                    CreatedAccountId = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    BoxId = table.Column<int>(type: "INTEGER", nullable: true),
                    Ip = table.Column<string>(type: "TEXT", nullable: true),
                    Service = table.Column<string>(type: "TEXT", nullable: true),
                    Username = table.Column<string>(type: "TEXT", nullable: false),
                    Password = table.Column<string>(type: "TEXT", nullable: true),
                    Privilege = table.Column<string>(type: "TEXT", nullable: true),
                    Notes = table.Column<string>(type: "TEXT", nullable: true),
                    CreatedBy = table.Column<string>(type: "TEXT", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "TEXT", nullable: false),
                    LinkedCredId = table.Column<int>(type: "INTEGER", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_CreatedAccount", x => x.CreatedAccountId);
                });

            migrationBuilder.CreateIndex(
                name: "IX_CreatedAccount_BoxId",
                table: "CreatedAccount",
                column: "BoxId");

            migrationBuilder.CreateIndex(
                name: "IX_CreatedAccount_Ip",
                table: "CreatedAccount",
                column: "Ip");

            migrationBuilder.CreateTable(
                name: "PivotEdge",
                columns: table => new
                {
                    PivotEdgeId = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    SourceIp = table.Column<string>(type: "TEXT", nullable: false),
                    TargetIp = table.Column<string>(type: "TEXT", nullable: false),
                    Technique = table.Column<string>(type: "TEXT", nullable: true),
                    Label = table.Column<string>(type: "TEXT", nullable: true),
                    CredId = table.Column<int>(type: "INTEGER", nullable: true),
                    CreatedBy = table.Column<string>(type: "TEXT", nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PivotEdge", x => x.PivotEdgeId);
                });

            migrationBuilder.CreateIndex(
                name: "IX_PivotEdge_SourceIp",
                table: "PivotEdge",
                column: "SourceIp");

            migrationBuilder.CreateIndex(
                name: "IX_PivotEdge_TargetIp",
                table: "PivotEdge",
                column: "TargetIp");

            migrationBuilder.CreateTable(
                name: "CredUsage",
                columns: table => new
                {
                    CredUsageId = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlite:Autoincrement", true),
                    CredId = table.Column<int>(type: "INTEGER", nullable: false),
                    BoxId = table.Column<int>(type: "INTEGER", nullable: true),
                    Ip = table.Column<string>(type: "TEXT", nullable: true),
                    Port = table.Column<int>(type: "INTEGER", nullable: true),
                    ServiceName = table.Column<string>(type: "TEXT", nullable: true),
                    Status = table.Column<string>(type: "TEXT", nullable: true),
                    Notes = table.Column<string>(type: "TEXT", nullable: true),
                    TestedBy = table.Column<string>(type: "TEXT", nullable: true),
                    TestedAt = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_CredUsage", x => x.CredUsageId);
                });

            migrationBuilder.CreateIndex(
                name: "IX_CredUsage_CredId",
                table: "CredUsage",
                column: "CredId");

            migrationBuilder.CreateIndex(
                name: "IX_CredUsage_BoxId",
                table: "CredUsage",
                column: "BoxId");
        }

        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(name: "CredUsage");
            migrationBuilder.DropTable(name: "PivotEdge");
            migrationBuilder.DropTable(name: "CreatedAccount");
            migrationBuilder.DropColumn(name: "Stage", table: "Boxes");
        }
    }
}
