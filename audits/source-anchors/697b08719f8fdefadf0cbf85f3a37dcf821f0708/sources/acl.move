module turbos_farming::acl {
    use sui::linked_table::{Self, LinkedTable};

    // === Errors ===

    const EInvalidRole: u64 = 0;
    const EMemberNotFound: u64 = 1;

    public struct ACL has key, store {
        id: UID,
        permissions: LinkedTable<address, u128>,
    }

    public struct Member has copy, drop, store {
        address: address,
        permission: u128,
    }

    public(package) fun new(ctx: &mut TxContext): ACL {
        ACL {
            id: object::new(ctx),
            permissions: linked_table::new(ctx),
        }
    }

    public(package) fun add_role(acl: &mut ACL, addr: address, role: u8) {
        assert!(role < 128, EInvalidRole);
        if (acl.permissions.contains(addr)) {
            let perm = acl.permissions.borrow_mut(addr);
            let mask = (1 << role);
            *perm = *perm | mask;
        } else {
            acl.permissions.push_back(addr, 1 << role);
        }
    }

    public fun get_members(acl: &ACL): vector<Member> {
        let mut members: vector<Member> = vector[];
        let mut current_opt = acl.permissions.front();
        while (current_opt.is_some()) {
            let current = current_opt.borrow();
            let permission = *acl.permissions.borrow(*current);
            members.push_back(Member { address: *current, permission });
            current_opt = acl.permissions.next(*current);
        };
        members
    }

    public fun get_permission(acl: &ACL, addr: address): u128 {
        if (!acl.permissions.contains(addr)) {
            0
        } else {
            *acl.permissions.borrow(addr)
        }
    }

    public fun has_role(acl: &ACL, address: address, role: u8): bool {
        assert!(role < 128, EInvalidRole);
        acl.permissions.contains(address) && ((*acl.permissions.borrow(address) & (1 << role)) > 0)
    }

    public(package) fun remove_member(acl: &mut ACL, addr: address) {
        assert!(acl.permissions.contains(addr), EMemberNotFound);
        if (acl.permissions.contains(addr)) {
            acl.permissions.remove(addr);
        }
    }

    public(package) fun remove_role(acl: &mut ACL, addr: address, role: u8) {
        assert!(role < 128, EInvalidRole);
        if (acl.permissions.contains(addr)) {
            let perm = acl.permissions.borrow_mut(addr);
            // like ~(1 << role)
            let mask = (1 << role) ^ 0xffffffffffffffffffffffffffffffff;
            *perm = *perm & mask;
        }
    }

    public(package) fun set_roles(acl: &mut ACL, addr: address, roles: u128) {
        if (acl.permissions.contains(addr)) {
            *acl.permissions.borrow_mut(addr) = roles;
        } else {
            acl.permissions.push_back(addr, roles);
        }
    }

    public fun get_member_address(member: &Member): address {
        member.address
    }
}