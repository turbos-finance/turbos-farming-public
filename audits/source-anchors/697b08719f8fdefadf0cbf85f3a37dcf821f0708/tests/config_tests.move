#[test_only]
module turbos_farming::config_tests {
    use turbos_farming::config::{Self};

    const ADMIN: address = @0x0;
    const USER: address = @0x1;

    #[test]
    fun test_roles_can_be_added_checked_and_removed() {
        let ctx = &mut tx_context::dummy();
        let (mut config, admin_cap) = config::new_config(ctx);

        config::set_roles(&admin_cap, &mut config, USER, 0);
        config::add_role(&admin_cap, &mut config, USER, 0);
        config::add_role(&admin_cap, &mut config, USER, 1);

        config::check_pool_manager_role(&config, USER);
        config::check_rewarder_manager_role(&config, USER);

        config::remove_role(&admin_cap, &mut config, USER, 1);
        assert!(vector::length(&config::get_members(&config)) == 1, 0);

        transfer::public_transfer(admin_cap, ADMIN);
        transfer::public_transfer(config, ADMIN);
    }

    #[test]
    fun test_emergency_pause_and_unpause_round_trip() {
        let ctx = &mut tx_context::dummy();
        let (mut config, admin_cap) = config::new_config(ctx);

        config::add_role(&admin_cap, &mut config, ADMIN, 2);
        config::emergency_pause(&mut config, ctx);
        config::emergency_unpause(&mut config, &admin_cap);
        config::checked_package_version(&config);

        transfer::public_transfer(admin_cap, ADMIN);
        transfer::public_transfer(config, ADMIN);
    }

    #[test]
    #[expected_failure(abort_code = 1, location = turbos_farming::config)]
    fun test_pool_manager_check_rejects_member_without_role() {
        let ctx = &mut tx_context::dummy();
        let (config, admin_cap) = config::new_config(ctx);

        config::check_pool_manager_role(&config, USER);

        transfer::public_transfer(admin_cap, ADMIN);
        transfer::public_transfer(config, ADMIN);
    }

    #[test]
    #[expected_failure(abort_code = 2, location = turbos_farming::config)]
    fun test_rewarder_manager_check_rejects_member_without_role() {
        let ctx = &mut tx_context::dummy();
        let (config, admin_cap) = config::new_config(ctx);

        config::check_rewarder_manager_role(&config, USER);

        transfer::public_transfer(admin_cap, ADMIN);
        transfer::public_transfer(config, ADMIN);
    }

    #[test]
    #[expected_failure(abort_code = 3, location = turbos_farming::config)]
    fun test_checked_package_version_rejects_emergency_pause_state() {
        let ctx = &mut tx_context::dummy();
        let (mut config, admin_cap) = config::new_config(ctx);

        config::add_role(&admin_cap, &mut config, ADMIN, 2);
        config::emergency_pause(&mut config, ctx);
        config::checked_package_version(&config);

        transfer::public_transfer(admin_cap, ADMIN);
        transfer::public_transfer(config, ADMIN);
    }
}
