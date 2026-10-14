#[test_only]
module turbos_farming::rewarder_tests {
    use turbos_farming::{
        config::{Self, AdminCap, GlobalConfig},
        rewarder::{Self, RewarderManager}
    };
    use std::type_name;
    use sui::{balance, clock::{Self, Clock}};

    const ADMIN: address = @0x0;
    const ACC_PRECISION: u256 = 1000000000000000000000000000000000000;

    public struct REWARD has drop {}

    fun new_pool_id(ctx: &mut TxContext): ID {
        let uid = object::new(ctx);
        let id = object::uid_to_inner(&uid);
        object::delete(uid);
        id
    }

    fun setup_rewarder(
        emission_per_second: u128,
        allocate_point: u64,
        ctx: &mut TxContext,
    ): (GlobalConfig, AdminCap, RewarderManager, Clock, ID) {
        let (mut config, admin_cap) = config::new_config(ctx);
        config::add_role(&admin_cap, &mut config, ADMIN, 1);

        let mut manager = rewarder::new_manager_for_testing(ctx);
        let clock = clock::create_for_testing(ctx);
        let pool_id = new_pool_id(ctx);

        rewarder::create_rewarder<REWARD>(
            &config,
            &mut manager,
            emission_per_second,
            &clock,
            ctx,
        );
        rewarder::register_pool(&mut manager, pool_id);
        rewarder::add_pool<REWARD>(&mut manager, pool_id, allocate_point, &clock);

        (config, admin_cap, manager, clock, pool_id)
    }

    #[test]
    fun test_pool_settlement_updates_release_and_acc_per_share() {
        let ctx = &mut tx_context::dummy();
        let (config, admin_cap, mut manager, mut clock, pool_id) = setup_rewarder(100, 10, ctx);

        rewarder::set_pool_share(&mut manager, pool_id, 1000);
        clock::increment_for_testing(&mut clock, 10_000);

        let reward_type = type_name::with_defining_ids<REWARD>();
        let settled = rewarder::pool_rewards_settle(
            &mut manager,
            vector[reward_type],
            pool_id,
            &clock,
        );

        // 100 rewards/sec * 10 sec / 1000 pool share = 1 reward/share.
        assert!(*settled.get(&reward_type) == ACC_PRECISION, 0);
        assert!(rewarder::pool_share(&manager, pool_id) == 1000, 1);

        let rewarder_ref = rewarder::borrow_rewarder<REWARD>(&manager);
        let pool_info = rewarder::borrow_pool_rewarder_info(rewarder_ref, pool_id);
        assert!(rewarder::pool_reward_released(pool_info) == 1000, 2);
        assert!(rewarder::total_reward_released(rewarder_ref) == 1000, 3);

        clock::destroy_for_testing(clock);
        transfer::public_transfer(admin_cap, ADMIN);
        transfer::public_transfer(config, ADMIN);
        transfer::public_transfer(manager, ADMIN);
    }

    #[test]
    fun test_multiple_pools_split_rewards_by_allocate_point() {
        let ctx = &mut tx_context::dummy();
        let (config, admin_cap, mut manager, mut clock, pool_a) = setup_rewarder(100, 10, ctx);
        let pool_b = new_pool_id(ctx);

        rewarder::register_pool(&mut manager, pool_b);
        rewarder::add_pool<REWARD>(&mut manager, pool_b, 30, &clock);
        rewarder::set_pool_share(&mut manager, pool_a, 10);
        rewarder::set_pool_share(&mut manager, pool_b, 10);
        clock::increment_for_testing(&mut clock, 10_000);

        let reward_type = type_name::with_defining_ids<REWARD>();
        let settled_a = rewarder::pool_rewards_settle(
            &mut manager,
            vector[reward_type],
            pool_a,
            &clock,
        );
        let settled_b = rewarder::pool_rewards_settle(
            &mut manager,
            vector[reward_type],
            pool_b,
            &clock,
        );

        // Total release is 100 * 10 = 1000; pools split it 10:30, then divide by share 10.
        assert!(*settled_a.get(&reward_type) == 25 * ACC_PRECISION, 0);
        assert!(*settled_b.get(&reward_type) == 75 * ACC_PRECISION, 1);

        let rewarder_ref = rewarder::borrow_rewarder<REWARD>(&manager);
        let pool_a_info = rewarder::borrow_pool_rewarder_info(rewarder_ref, pool_a);
        let pool_b_info = rewarder::borrow_pool_rewarder_info(rewarder_ref, pool_b);

        assert!(rewarder::pool_reward_released(pool_a_info) == 250, 2);
        assert!(rewarder::pool_reward_released(pool_b_info) == 750, 3);
        assert!(rewarder::total_reward_released(rewarder_ref) == 1000, 4);

        clock::destroy_for_testing(clock);
        transfer::public_transfer(admin_cap, ADMIN);
        transfer::public_transfer(config, ADMIN);
        transfer::public_transfer(manager, ADMIN);
    }

    #[test]
    fun test_zero_pool_share_settlement_preserves_pool_accumulator() {
        let ctx = &mut tx_context::dummy();
        let (config, admin_cap, mut manager, mut clock, pool_id) = setup_rewarder(100, 10, ctx);

        clock::increment_for_testing(&mut clock, 10_000);

        let reward_type = type_name::with_defining_ids<REWARD>();
        let settled = rewarder::pool_rewards_settle(
            &mut manager,
            vector[reward_type],
            pool_id,
            &clock,
        );

        assert!(*settled.get(&reward_type) == 0, 0);

        let rewarder_ref = rewarder::borrow_rewarder<REWARD>(&manager);
        let pool_info = rewarder::borrow_pool_rewarder_info(rewarder_ref, pool_id);
        assert!(rewarder::pool_reward_released(pool_info) == 0, 1);
        assert!(rewarder::pool_acc_per_share(pool_info) == 0, 2);

        clock::destroy_for_testing(clock);
        transfer::public_transfer(admin_cap, ADMIN);
        transfer::public_transfer(config, ADMIN);
        transfer::public_transfer(manager, ADMIN);
    }

    #[test]
    fun test_high_precision_pool_share_preserves_small_reward_accumulator() {
        let ctx = &mut tx_context::dummy();
        let (config, admin_cap, mut manager, mut clock, pool_id) = setup_rewarder(1, 10, ctx);

        rewarder::set_pool_share(&mut manager, pool_id, 10000000000000000000000000000);
        clock::increment_for_testing(&mut clock, 10_000);

        let reward_type = type_name::with_defining_ids<REWARD>();
        let settled = rewarder::pool_rewards_settle(
            &mut manager,
            vector[reward_type],
            pool_id,
            &clock,
        );

        assert!(*settled.get(&reward_type) == 1000000000, 0);

        let rewarder_ref = rewarder::borrow_rewarder<REWARD>(&manager);
        let pool_info = rewarder::borrow_pool_rewarder_info(rewarder_ref, pool_id);
        assert!(rewarder::pool_reward_released(pool_info) == 10, 1);
        assert!(rewarder::total_reward_released(rewarder_ref) == 10, 2);

        clock::destroy_for_testing(clock);
        transfer::public_transfer(admin_cap, ADMIN);
        transfer::public_transfer(config, ADMIN);
        transfer::public_transfer(manager, ADMIN);
    }

    #[test]
    fun test_deposit_and_withdraw_reward_vault_balance() {
        let ctx = &mut tx_context::dummy();
        let (config, admin_cap, mut manager, clock, _pool_id) = setup_rewarder(100, 10, ctx);

        rewarder::deposit_rewarder<REWARD>(
            &config,
            &mut manager,
            balance::create_for_testing<REWARD>(5000),
        );

        assert!(rewarder::vault_balance<REWARD>(&manager) == 5000, 0);

        let withdrawn = rewarder::emergent_withdraw<REWARD>(
            &admin_cap,
            &config,
            &mut manager,
            1200,
        );

        assert!(balance::value(&withdrawn) == 1200, 1);
        assert!(rewarder::vault_balance<REWARD>(&manager) == 3800, 2);
        balance::destroy_for_testing(withdrawn);

        clock::destroy_for_testing(clock);
        transfer::public_transfer(admin_cap, ADMIN);
        transfer::public_transfer(config, ADMIN);
        transfer::public_transfer(manager, ADMIN);
    }

    #[test]
    fun test_emergent_withdraw_allows_emergency_paused_config() {
        let ctx = &mut tx_context::dummy();
        let (mut config, admin_cap, mut manager, clock, _pool_id) = setup_rewarder(100, 10, ctx);

        rewarder::deposit_rewarder<REWARD>(
            &config,
            &mut manager,
            balance::create_for_testing<REWARD>(5000),
        );

        config::add_role(&admin_cap, &mut config, ADMIN, 2);
        config::emergency_pause(&mut config, ctx);
        let withdrawn = rewarder::emergent_withdraw<REWARD>(
            &admin_cap,
            &config,
            &mut manager,
            1200,
        );

        assert!(balance::value(&withdrawn) == 1200, 0);
        assert!(rewarder::vault_balance<REWARD>(&manager) == 3800, 1);

        balance::destroy_for_testing(withdrawn);
        clock::destroy_for_testing(clock);
        transfer::public_transfer(admin_cap, ADMIN);
        transfer::public_transfer(config, ADMIN);
        transfer::public_transfer(manager, ADMIN);
    }

    #[test]
    #[expected_failure(abort_code = 2, location = turbos_farming::config)]
    fun test_create_rewarder_rejects_sender_without_role() {
        let ctx = &mut tx_context::dummy();
        let (config, admin_cap) = config::new_config(ctx);
        let mut manager = rewarder::new_manager_for_testing(ctx);
        let clock = clock::create_for_testing(ctx);

        rewarder::create_rewarder<REWARD>(&config, &mut manager, 100, &clock, ctx);

        clock::destroy_for_testing(clock);
        transfer::public_transfer(admin_cap, ADMIN);
        transfer::public_transfer(config, ADMIN);
        transfer::public_transfer(manager, ADMIN);
    }

    #[test]
    #[expected_failure(abort_code = 3, location = turbos_farming::config)]
    fun test_create_rewarder_rejects_emergency_paused_config() {
        let ctx = &mut tx_context::dummy();
        let (mut config, admin_cap) = config::new_config(ctx);
        let mut manager = rewarder::new_manager_for_testing(ctx);
        let clock = clock::create_for_testing(ctx);

        config::add_role(&admin_cap, &mut config, ADMIN, 1);
        config::add_role(&admin_cap, &mut config, ADMIN, 2);
        config::emergency_pause(&mut config, ctx);
        rewarder::create_rewarder<REWARD>(&config, &mut manager, 100, &clock, ctx);

        clock::destroy_for_testing(clock);
        transfer::public_transfer(admin_cap, ADMIN);
        transfer::public_transfer(config, ADMIN);
        transfer::public_transfer(manager, ADMIN);
    }

    #[test]
    #[expected_failure(abort_code = 5, location = turbos_farming::rewarder)]
    fun test_withdraw_reward_rejects_insolvent_vault() {
        let ctx = &mut tx_context::dummy();
        let (config, admin_cap, mut manager, clock, pool_id) = setup_rewarder(100, 10, ctx);

        rewarder::deposit_rewarder<REWARD>(
            &config,
            &mut manager,
            balance::create_for_testing<REWARD>(100),
        );

        let withdrawn = rewarder::withdraw_reward<REWARD>(&mut manager, pool_id, 101);

        balance::destroy_for_testing(withdrawn);
        clock::destroy_for_testing(clock);
        transfer::public_transfer(admin_cap, ADMIN);
        transfer::public_transfer(config, ADMIN);
        transfer::public_transfer(manager, ADMIN);
    }
}
