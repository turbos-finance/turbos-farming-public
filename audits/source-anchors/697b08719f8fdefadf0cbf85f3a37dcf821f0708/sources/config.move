module turbos_farming::config {
    use turbos_farming::acl::{Self, ACL};
    use sui::event;

    const ACL_POOL_MANAGER: u8 = 0;
    const ACL_REWARDER_MANAGER: u8 = 1;
    const ACL_EMERGENCY_PAUSE: u8 = 2;

    const VERSION: u64 = 1;

    const ENoPoolManagerPermission: u64 = 1;
    const ENoRewarderManagerPermission: u64 = 2;
    const EPackageVersionDeprecate: u64 = 3;
    const EEmergencyVersionDeprecate: u64 = 4;
    const ENoEmergencyPausePermission: u64 = 5;
    const EVersionDowngrade: u64 = 6;
    const ENotEmergencyPaused: u64 = 7;

    public struct AdminCap has key, store {
        id: UID,
    }

    public struct GlobalConfig has key, store {
        id: UID,
        acl: ACL,
        package_version: u64,
    }

    public struct InitConfigEvent has copy, drop {
        admin_cap_id: ID,
        global_config_id: ID,
    }

    public struct SetRolesEvent has copy, drop {
        member: address,
        roles: u128,
    }

    public struct AddRoleEvent has copy, drop {
        member: address,
        role: u8,
    }

    public struct RemoveRoleEvent has copy, drop {
        member: address,
        role: u8,
    }

    public struct RemoveMemberEvent has copy, drop {
        member: address,
    }

    public struct SetPackageVersion has copy, drop {
        new_version: u64,
        old_version: u64,
    }

    fun init(ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let mut config = GlobalConfig {
            id: object::new(ctx),
            acl: acl::new(ctx),
            package_version: VERSION,
        };
        let cap = AdminCap { id: object::new(ctx) };
        let config_id = object::id(&config);
        let cap_id = object::id(&cap);
        set_roles(&cap, &mut config, sender, 7);
        transfer::transfer(cap, sender);
        transfer::share_object(config);
        event::emit(InitConfigEvent {
            admin_cap_id: cap_id,
            global_config_id: config_id,
        });
    }

    public fun set_roles(
        _: &AdminCap,
        config: &mut GlobalConfig,
        member: address,
        roles: u128,
    ) {
        checked_package_version(config);
        acl::set_roles(&mut config.acl, member, roles);
        event::emit(SetRolesEvent { member, roles });
    }

    public fun add_role(
        _: &AdminCap,
        config: &mut GlobalConfig,
        member: address,
        role: u8,
    ) {
        checked_package_version(config);
        acl::add_role(&mut config.acl, member, role);
        event::emit(AddRoleEvent { member, role });
    }

    public fun remove_role(
        _: &AdminCap,
        config: &mut GlobalConfig,
        member: address,
        role: u8,
    ) {
        checked_package_version(config);
        acl::remove_role(&mut config.acl, member, role);
        event::emit(RemoveRoleEvent { member, role });
    }

    public fun remove_member(_: &AdminCap, config: &mut GlobalConfig, member: address) {
        checked_package_version(config);
        acl::remove_member(&mut config.acl, member);
        event::emit(RemoveMemberEvent { member });
    }

    public fun set_package_version(_: &AdminCap, config: &mut GlobalConfig, version: u64) {
        assert!(version > config.package_version && version <= package_version(), EVersionDowngrade);
        let old_version = config.package_version;
        config.package_version = version;
        event::emit(SetPackageVersion {
            new_version: version,
            old_version,
        });
    }

    public fun get_members(config: &GlobalConfig): vector<acl::Member> {
        acl::get_members(&config.acl)
    }

    public fun check_pool_manager_role(config: &GlobalConfig, member: address) {
        assert!(acl::has_role(&config.acl, member, ACL_POOL_MANAGER), ENoPoolManagerPermission);
    }

    public fun check_rewarder_manager_role(config: &GlobalConfig, member: address) {
        assert!(
            acl::has_role(&config.acl, member, ACL_REWARDER_MANAGER),
            ENoRewarderManagerPermission,
        );
    }

    public fun checked_package_version(config: &GlobalConfig) {
        assert!(package_version() >= config.package_version, EPackageVersionDeprecate);
    }

    public fun package_version(): u64 {
        VERSION
    }

    public fun check_emergency_pause_role(config: &GlobalConfig, member: address) {
        assert!(acl::has_role(&config.acl, member, ACL_EMERGENCY_PAUSE), ENoEmergencyPausePermission);
    }

    public fun check_emergency_restore_version(config: &GlobalConfig) {
        assert!(config.package_version == 18446744073709551000, EEmergencyVersionDeprecate);
    }

    public fun emergency_pause(config: &mut GlobalConfig, ctx: &tx_context::TxContext) {
        check_emergency_pause_role(config, tx_context::sender(ctx));
        config.package_version = 9223372036854775808;
    }

    public fun emergency_unpause(config: &mut GlobalConfig, _: &AdminCap) {
        assert!(config.package_version == 9223372036854775808, ENotEmergencyPaused);
        config.package_version = package_version();
    }

    #[test_only]
    public fun new_config(ctx: &mut TxContext): (GlobalConfig, AdminCap) {
        let config = GlobalConfig {
            id: object::new(ctx),
            acl: acl::new(ctx),
            package_version: 0,
        };
        let cap = AdminCap {
            id: object::new(ctx),
        };
        (config, cap)
    }
}
