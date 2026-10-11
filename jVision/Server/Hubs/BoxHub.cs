using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.SignalR;
using jVision.Shared;
using jVision.Server.Models;
using jVision.Shared.Models;

namespace jVision.Server.Hubs
{
    public interface IBoxClient
    {
        //how u get rid these param
        Task BoxAdded();
        Task UserAdded(string s);
        Task BoxUpdated(BoxDTO b);

        Task BoxUpgraded(List<BoxDTO> b);
        Task BoxDeleted(int boxId);
        Task BoxesCleared();
        Task CredAdded(Cred c);
        Task CredUpdated(Cred c);
        Task CredDeleted(int c);
        Task LogsAdded(int count);
        Task ScratchChanged();
        Task ScanUploaded(ScanUpload s);
        Task ScanDeleted(int id);
        Task CustomTabsChanged();

        // Single "something changed on this resource" pings; each page re-fetches
        // rather than merging per-op deltas. Simpler than CredAdded/Updated/Deleted
        // and enough for the low-cardinality resources these back.
        Task CreatedAccountsChanged();
        Task PivotEdgesChanged();
        Task CredUsagesChanged();

        // (boxId, list of user names currently viewing that box).
        Task BoxPresenceChanged(int boxId, List<string> users);
    }
    public class BoxHub : Hub<IBoxClient>
    {
        // Presence tracking: for each open box, remember which connection ids
        // are viewing it, and for each connection remember which boxes it's in
        // (so we can clean up on disconnect without walking every box).
        //
        // Static because IBoxClient hub is transient per request. Fine for a
        // single-process app; would need a backplane if the server scaled out.
        private static readonly ConcurrentDictionary<int, ConcurrentDictionary<string, string>> _boxViewers = new();
        private static readonly ConcurrentDictionary<string, HashSet<int>> _connectionBoxes = new();

        private static string GroupName(int boxId) => $"box:{boxId}";

        public async Task JoinBox(int boxId, string userName)
        {
            var name = string.IsNullOrWhiteSpace(userName) ? "anon" : userName.Trim();
            await Groups.AddToGroupAsync(Context.ConnectionId, GroupName(boxId));

            var viewers = _boxViewers.GetOrAdd(boxId, _ => new ConcurrentDictionary<string, string>());
            viewers[Context.ConnectionId] = name;

            _connectionBoxes.AddOrUpdate(Context.ConnectionId,
                _ => new HashSet<int> { boxId },
                (_, set) => { set.Add(boxId); return set; });

            await BroadcastPresence(boxId);
        }

        public async Task LeaveBox(int boxId)
        {
            await Groups.RemoveFromGroupAsync(Context.ConnectionId, GroupName(boxId));

            if (_boxViewers.TryGetValue(boxId, out var viewers))
            {
                viewers.TryRemove(Context.ConnectionId, out _);
                if (viewers.IsEmpty) _boxViewers.TryRemove(boxId, out _);
            }
            if (_connectionBoxes.TryGetValue(Context.ConnectionId, out var set))
            {
                set.Remove(boxId);
            }
            await BroadcastPresence(boxId);
        }

        private async Task BroadcastPresence(int boxId)
        {
            List<string> users;
            if (_boxViewers.TryGetValue(boxId, out var viewers))
                users = viewers.Values.Distinct().OrderBy(u => u).ToList();
            else
                users = new List<string>();
            await Clients.All.BoxPresenceChanged(boxId, users);
        }

        public override async Task OnConnectedAsync()
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, "SignalR Users");
            await base.OnConnectedAsync();
        }
        public override async Task OnDisconnectedAsync(Exception exception)
        {
            await Groups.RemoveFromGroupAsync(Context.ConnectionId, "SingalR Users");

            // Drop this connection from every box presence set it was in and
            // rebroadcast so viewers see it leave.
            if (_connectionBoxes.TryRemove(Context.ConnectionId, out var boxes))
            {
                foreach (var boxId in boxes.ToList())
                {
                    if (_boxViewers.TryGetValue(boxId, out var viewers))
                    {
                        viewers.TryRemove(Context.ConnectionId, out _);
                        if (viewers.IsEmpty) _boxViewers.TryRemove(boxId, out _);
                    }
                    await BroadcastPresence(boxId);
                }
            }

            await base.OnDisconnectedAsync(exception);
        }
    }
}
