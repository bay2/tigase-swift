//
// Room.swift
//
// TigaseSwift
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
//

import Foundation

/**
 Class represents MUC room locally and supports `ChatProtocol`
 */
public class Room: ChatProtocol, ContextAware {

    private static let stampFormatter = ({()-> NSDateFormatter in
        var f = NSDateFormatter();
        f.locale = NSLocale(localeIdentifier: "en_US_POSIX");
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ";
        f.timeZone = NSTimeZone(forSecondsFromGMT: 0);
        return f;
    })();
    
    // common variables
    /// JID of MUC room
    private var _jid: JID;
    public var jid: JID {
        get {
            var result: JID! = nil;
            dispatch_sync(Room.queue) {
                result = self._jid;
            }
            return result;
        }
        set {
            dispatch_barrier_async(Room.queue) {
                self._jid = newValue;
            }
        }
    }
    public let allowFullJid: Bool = false;
    
    // specific variables
    public var context: Context!;
    
    private var _lastMessageDate: NSDate? = nil;
    /// Timestamp of last received message
    public var lastMessageDate: NSDate? {
        get {
            var result: NSDate? = nil;
            dispatch_sync(Room.queue) {
                result = self._lastMessageDate;
            }
            return result;
        }
        set {
            guard newValue != nil else {
                return;
            }
            dispatch_barrier_async(Room.queue) {
                if self._lastMessageDate == nil || self._lastMessageDate!.compare(newValue!) == NSComparisonResult.OrderedAscending {
                    self._lastMessageDate = newValue;
                }
            }
        }
    }
    
    private let _nickname: String;
    /// Nickname in room
    public var nickname: String {
        return _nickname;
    }
    
    private var _password: String?;
    /// Room password
    public var password: String? {
        get {
            var result: String? = nil;
            dispatch_sync(Room.queue) {
                result = self._password;
            }
            return result;
        }
        set {
            dispatch_barrier_async(Room.queue) {
                self._password = newValue;
            }
        }
    }
    
    private var _presences = [String: Occupant]();
    /// Room occupants
    public var presences: [String: Occupant] {
        var result: [String: Occupant]!;
        dispatch_sync(Room.queue) {
            result = self._presences;
        }
        return result;
    }
    /// BareJID of MUC room
    public var roomJid: BareJID {
        get {
            return jid.bareJid;
        }
    }
    
    var _state: State = .not_joined;
    /// State of room
    public var state: State {
        return _state;
    }
    
    private static let queue = dispatch_queue_create("room_queue", DISPATCH_QUEUE_CONCURRENT);
    
    private var _tempOccupants = [String:Occupant]();
    /// Temporary occupants
    public var tempOccupants: [String:Occupant] {
        var result: [String: Occupant]!;
        dispatch_sync(Room.queue) {
            result = self._tempOccupants;
        }
        return result;
    }
    
    public init(context: Context, roomJid: BareJID, nickname: String) {
        self.context = context;
        self._nickname = nickname;
        self._jid = JID(roomJid);
    }
    
    /// Rejoin this room
    public func rejoin() -> Presence {
        let presence = Presence();
        presence.to = JID(roomJid, resource: nickname);
        let x = Element(name: "x", xmlns: "http://jabber.org/protocol/muc");
        presence.addChild(x);
        if password != nil {
            x.addChild(Element(name: "password", cdata: password!));
        }
        
        if lastMessageDate != nil {
            let history = Element(name: "history");
            history.setAttribute("since", value: Room.stampFormatter.stringFromDate(lastMessageDate!));
            x.addChild(history);
        }
        
        _state = .requested;
        context.writer?.write(presence);
        return presence;
    }
    
    /**
     Send message to room
     - parameter body: text to send
     - parameter additionalElement: additional elements to add to message
     */
    public func sendMessage(body: String?, additionalElements: [Element]? = nil) {
        let msg = createMessage(body);
        if additionalElements != nil {
            for elem in additionalElements! {
                msg.addChild(elem);
            }
        }
        context.writer?.write(msg);
    }
    
    /**
     Prepare message for sending to room
     - parameter body: text to send
     - returns: newly create message
     */
    public func createMessage(body: String?) -> Message {
        var msg = Message();
        msg.to = jid;
        msg.type = StanzaType.groupchat;
        msg.body = body;
        return msg;
    }
    
    /**
     Send invitation
     - parameter invitee: user to invite
     - parameter reason: invitation reason
     */
    public func invite(invitee: JID, reason: String?) {
        let message = self.createInvitation(invitee, reason: reason);
        
        context.writer?.write(message);
    }
    
    /**
     Create invitation
     - parameter invitee: user to invite
     - parameter reason: invitation reason
     - returns: newly create message
     */
    public func createInvitation(invitee: JID, reason: String?) -> Message {
        let message = Message();
        message.to = JID(self.roomJid);
        
        let x = Element(name: "x", xmlns: "http://jabber.org/protocol/muc#user");
        let invite = Element(name: "invite");
        invite.setAttribute("to", value: invitee.stringValue);
        if (reason != nil) {
            invite.addChild(Element(name: "reason", cdata: reason!));
        }
        x.addChild(invite);
        message.addChild(x);

        return message;
    }
    
    /**
     Send direct invitation
     - parameter invitee: user to invite
     - parameter reason: invitation reason
     - parameter threadId: thread id to use in invitation message
     */
    public func inviteDirectly(invitee: JID, reason: String?, threadId: String?) {
        let message = createDirectInvitation(invitee, reason: reason, threadId: threadId);
        context.writer?.write(message);
    }
    
    /**
     Create direct invitation
     - parameter invitee: user to invite
     - parameter reason: invitation reason
     - parameter threadId: thread id to use in invitation message
     - returns: newly created invitation message
     */
    public func createDirectInvitation(invitee: JID, reason: String?, threadId: String?) -> Message {
        let message = Message();
        message.to = invitee;
        
        let x = Element(name: "x", xmlns: "jabber:x:conference");
        x.setAttribute("jid", value: roomJid.stringValue);
        
        x.setAttribute("password", value: password);
        x.setAttribute("reason", value: reason);
        
        if threadId != nil {
            x.setAttribute("thread", value: threadId);
            x.setAttribute("continue", value: "true");
        }
        
        return message;
    }
    
    public func add(occupant: Occupant) {
        dispatch_barrier_async(Room.queue) {
            self._presences[occupant.nickname] = occupant;
        }
    }
    
    public func remove(occupant: Occupant) {
        dispatch_barrier_async(Room.queue) {
            self._presences.removeValueForKey(occupant.nickname);
        }
    }
    
    public func addTemp(nickname: String, occupant: Occupant) {
        dispatch_barrier_async(Room.queue) {
            self._tempOccupants[nickname] = occupant;
        }
    }
    
    public func removeTemp(nickname: String) -> Occupant? {
        var result: Occupant?;
        dispatch_barrier_sync(Room.queue) {
            result = self._tempOccupants.removeValueForKey(nickname);
        }
        return result;
    }
    
    /**
     Possible states of room:
     - joined: you are joined to room
     - not_joined: you are not joined and join is not it progress
     - requested: you are not joined but already requested join
     */
    public enum State {
        case joined
        case not_joined
        case requested
    }
}