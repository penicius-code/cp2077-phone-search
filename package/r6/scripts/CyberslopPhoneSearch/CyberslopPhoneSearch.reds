// Cyberslop Phone Search 1.0.1 - redscript half of the CET window "Phone Search".
//
// Snapshot() lists what the vanilla phone lists: the Contacts tab (MessengerUtils.GetCallableAndNonEmptyContacts)
// and every message thread, read ones too (MessengerUtils.GetSimpleContactDataArray with includeWithNoUnread).
// Mods that add phone contacts (NightlyNow Holo: Drug Dealer's Yukmouth / Shanice, NC Cab, Trauma Team, GigCore,
// NCPD Duty ...) wrap those same functions, so their contacts show up here too.
//
// OpenThread(hash) opens the vanilla phone on one thread the way a message notification does: the HUD's
// m_messageToOpenHash is set, then a UsePhoneRequest opens the contact list, which selects that thread on the
// Unread tab and focuses the messenger. "Show all" is switched on for that one opening (so read threads are in
// the list) and switched back when the contact list closes.
//
// 1.0.1: a contact that has messages but no row in the message list (a Holo contact once it is read and not
// pinned: Holo then lists it on the Contacts tab only) gets a thread row in Snapshot() too. OpenThread() remembers
// its hash, and the GetSimpleContactDataArray wrap below adds that contact's thread to the message list for that one
// opening, so the phone can select it. The hash is dropped when the contact list closes.
//
// Call(contactId) queues the same questTriggerCallRequest the dialer's Call button does
// (NewHudPhoneGameController.CallSelectedContact), after the same IsCallingEnabled check.

public class CyberslopPhoneEntry {
  public let name: String;
  public let title: String;
  public let contactId: String;
  public let contactHash: Int32;
  public let openHash: Int32;
  public let isThread: Bool;
  public let callable: Bool;
  public let unread: Int32;
  public let questRelated: Bool;
  public let canReply: Bool;
  public let timeSeconds: Int32;
}

public class CyberslopPhoneSearchSystem extends ScriptableSystem {
  private let m_hud: wref<NewHudPhoneGameController>;
  private let m_restoreShowAll: Bool;
  private let m_forceHash: Int32;

  public static func Get(game: GameInstance) -> ref<CyberslopPhoneSearchSystem> {
    return GameInstance.GetScriptableSystemsContainer(game).Get(n"CyberslopPhoneSearchSystem") as CyberslopPhoneSearchSystem;
  }

  public func SetHud(hud: ref<NewHudPhoneGameController>) {
    this.m_hud = hud;
  }

  public func ClearHud(hud: ref<NewHudPhoneGameController>) {
    if this.m_hud == hud {
      this.m_hud = null;
    }
  }

  public func HasHud() -> Bool {
    return IsDefined(this.m_hud);
  }

  private func GetPhone() -> ref<PhoneSystem> {
    return GameInstance.GetScriptableSystemsContainer(this.GetGameInstance()).Get(n"PhoneSystem") as PhoneSystem;
  }

  private func IsContactListOpen() -> Bool {
    let bb = GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().UI_ComDevice);
    if !IsDefined(bb) {
      return false;
    }
    return bb.GetBool(GetAllBlackboardDefs().UI_ComDevice.ContactsActive);
  }

  private static func Loc(raw: String) -> String {
    if !IsStringValid(raw) {
      return "";
    }
    let text = GetLocalizedText(raw);
    if !IsStringValid(text) {
      return raw;
    }
    return text;
  }

  private static func MakeEntry(c: ref<ContactData>, isThread: Bool) -> ref<CyberslopPhoneEntry> {
    let e = new CyberslopPhoneEntry();
    e.name = CyberslopPhoneSearchSystem.Loc(c.localizedName);
    e.contactId = c.contactId;
    e.contactHash = c.hash;
    e.isThread = isThread;
    e.callable = c.isCallable;
    e.questRelated = c.questRelated || c.hasQuestImportantReply;
    e.canReply = c.playerCanReply;
    if isThread {
      if c.hasValidTitle {
        e.title = CyberslopPhoneSearchSystem.Loc(c.localizedPreview);
      }
      e.openHash = Equals(c.type, MessengerContactType.MultiThread) ? c.conversationHash : c.hash;
      e.unread = ArraySize(c.unreadMessages);
      e.timeSeconds = GameTime.GetSeconds(c.timeStamp);
    } else {
      e.openHash = c.hash;
      e.unread = c.unreadMessegeCount;
    }
    return e;
  }

  private static func HasHash(list: array<ref<IScriptable>>, hash: Int32) -> Bool {
    for item in list {
      let c = item as ContactData;
      if IsDefined(c) && (c.hash == hash || c.conversationHash == hash) {
        return true;
      }
    }
    return false;
  }

  // The message list plus, while OpenThread() waits for the phone, the thread of the contact it asked for.
  public func AddForcedThread(journal: ref<JournalManager>, list: array<ref<IScriptable>>) -> array<ref<IScriptable>> {
    let hash = this.m_forceHash;
    if hash == 0 || !IsDefined(journal) || CyberslopPhoneSearchSystem.HasHash(list, hash) {
      return list;
    }
    let threads = MessengerUtils.GetMessageDataArrayForContact(journal, hash, true, true);
    for item in threads {
      let t = item as ContactData;
      if IsDefined(t) && NotEquals(t.type, MessengerContactType.Fake_ShowAll) {
        ArrayPush(list, t);
      }
    }
    return list;
  }

  // Contacts tab rows (isThread false) followed by message threads (isThread true).
  public func Snapshot() -> array<ref<CyberslopPhoneEntry>> {
    let result: array<ref<CyberslopPhoneEntry>>;
    let journal = GameInstance.GetJournalManager(this.GetGameInstance());
    if !IsDefined(journal) {
      return result;
    }
    let contacts = MessengerUtils.GetCallableAndNonEmptyContacts(journal);
    for item in contacts {
      let c = item as ContactData;
      if IsDefined(c) && NotEquals(c.type, MessengerContactType.Fake_ShowAll) {
        ArrayPush(result, CyberslopPhoneSearchSystem.MakeEntry(c, false));
      }
    }
    let threads = MessengerUtils.GetSimpleContactDataArray(journal, true, true, true);
    for item in threads {
      let t = item as ContactData;
      if IsDefined(t) && NotEquals(t.type, MessengerContactType.Fake_ShowAll) {
        ArrayPush(result, CyberslopPhoneSearchSystem.MakeEntry(t, true));
      }
    }
    // Contacts with messages that the message list leaves out (read Holo contacts): one thread row each.
    for item in contacts {
      let c = item as ContactData;
      if IsDefined(c) && NotEquals(c.type, MessengerContactType.Fake_ShowAll) && c.hash != 0
          && (c.hasMessages || c.messagesCount > 0) && !CyberslopPhoneSearchSystem.HasHash(threads, c.hash) {
        let e = CyberslopPhoneSearchSystem.MakeEntry(c, false);
        e.isThread = true;
        e.unread = 0;
        ArrayPush(result, e);
      }
    }
    return result;
  }

  // 0 = phone opening, 1 = phone HUD not ready, 2 = phone blocked (combat, scene ...), 3 = phone already open,
  // 4 = no such hash
  public func OpenThread(openHash: Int32) -> Int32 {
    if openHash == 0 {
      return 4;
    }
    let hud = this.m_hud;
    let phone = this.GetPhone();
    if !IsDefined(hud) || !IsDefined(phone) {
      return 1;
    }
    if !phone.IsPhoneEnabled() {
      return 2;
    }
    if this.IsContactListOpen() {
      return 3;
    }
    if !hud.m_isShowingAllMessages {
      hud.m_isShowingAllMessages = true;
      this.m_restoreShowAll = true;
    }
    this.m_forceHash = openHash;
    hud.m_messageToOpenHash = openHash;
    phone.QueueRequest(new UsePhoneRequest());
    return 0;
  }

  // 0 = calling, 1 = phone HUD not ready, 2 = calling blocked (combat, call running ...), 5 = not callable
  public func Call(contactId: String) -> Int32 {
    if !IsStringValid(contactId) {
      return 5;
    }
    let phone = this.GetPhone();
    if !IsDefined(phone) {
      return 1;
    }
    let journal = GameInstance.GetJournalManager(this.GetGameInstance());
    if !IsDefined(journal) {
      return 1;
    }
    let target: ref<ContactData>;
    let contacts = MessengerUtils.GetCallableAndNonEmptyContacts(journal);
    for item in contacts {
      let c = item as ContactData;
      if IsDefined(c) && c.isCallable && Equals(c.contactId, contactId) {
        target = c;
      }
    }
    if !IsDefined(target) {
      return 5;
    }
    if !phone.IsCallingEnabled() {
      return 2;
    }
    if IsDefined(this.m_hud) {
      this.m_hud.CallSelectedContact(target);
    } else {
      let request = new questTriggerCallRequest();
      request.addressee = StringToName(target.contactId);
      request.caller = n"Player";
      request.callPhase = questPhoneCallPhase.IncomingCall;
      request.callMode = questPhoneCallMode.Video;
      phone.QueueRequest(request);
    }
    return 0;
  }

  public func OnContactListClosed(hud: ref<NewHudPhoneGameController>) {
    this.m_forceHash = 0;
    if this.m_restoreShowAll {
      this.m_restoreShowAll = false;
      if IsDefined(hud) {
        hud.m_isShowingAllMessages = false;
      }
    }
  }
}

@wrapMethod(NewHudPhoneGameController)
protected cb func OnInitialize() -> Bool {
  let result = wrappedMethod();
  if IsDefined(this.m_player) {
    let sys = CyberslopPhoneSearchSystem.Get(this.m_player.GetGame());
    if IsDefined(sys) {
      sys.SetHud(this);
    }
  }
  return result;
}

@wrapMethod(NewHudPhoneGameController)
protected cb func OnUninitialize() -> Bool {
  if IsDefined(this.m_player) {
    let sys = CyberslopPhoneSearchSystem.Get(this.m_player.GetGame());
    if IsDefined(sys) {
      sys.ClearHud(this);
    }
  }
  return wrappedMethod();
}

@wrapMethod(NewHudPhoneGameController)
protected cb func OnContactListClosed() -> Bool {
  let result = wrappedMethod();
  if IsDefined(this.m_player) {
    let sys = CyberslopPhoneSearchSystem.Get(this.m_player.GetGame());
    if IsDefined(sys) {
      sys.OnContactListClosed(this);
    }
  }
  return result;
}

@wrapMethod(MessengerUtils)
public final static func GetSimpleContactDataArray(journal: ref<JournalManager>, includeUnknown: Bool, skipEmpty: Bool, includeWithNoUnread: Bool, opt activeDataSync: wref<MessengerContactSyncData>) -> array<ref<IScriptable>> {
  let list = wrappedMethod(journal, includeUnknown, skipEmpty, includeWithNoUnread, activeDataSync);
  let sys = CyberslopPhoneSearchSystem.Get(GetGameInstance());
  if IsDefined(sys) {
    return sys.AddForcedThread(journal, list);
  }
  return list;
}
