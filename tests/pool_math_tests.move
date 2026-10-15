#[test_only]
module turbos_farming::pool_math_tests {
    use turbos_farming::pool;
    use turbos_clmm::i32;

    const Q64: u128 = 18446744073709551616;
    const LIQUIDITY: u128 = 1_000_000;
    const USER: address = @0x0;

    fun new_id(ctx: &mut TxContext): ID {
        let uid = object::new(ctx);
        let id = object::uid_to_inner(&uid);
        object::delete(uid);
        id
    }

    #[test]
    fun test_share_is_zero_when_position_does_not_overlap_effective_range() {
        let share = pool::calculate_position_share(
            i32::neg_from(100),
            i32::from(100),
            LIQUIDITY,
            Q64,
            i32::from(200),
            i32::from(300),
        );

        assert!(share == 0, 0);
    }

    #[test]
    fun test_share_matches_exact_value_for_centered_overlap() {
        let share = pool::calculate_position_share(
            i32::neg_from(100),
            i32::from(100),
            LIQUIDITY,
            Q64,
            i32::neg_from(50),
            i32::from(50),
        );

        assert!(share == 4992, 0);
    }

    #[test]
    fun test_share_matches_exact_value_for_single_sided_overlap() {
        let share = pool::calculate_position_share(
            i32::from(50),
            i32::from(100),
            LIQUIDITY,
            Q64,
            i32::from(50),
            i32::from(100),
        );

        assert!(share == 2490, 0);
    }

    #[test]
    fun test_share_matches_exact_value_for_full_position_overlap() {
        let share = pool::calculate_position_share(
            i32::neg_from(100),
            i32::from(100),
            LIQUIDITY,
            Q64,
            i32::neg_from(100),
            i32::from(100),
        );

        assert!(share == 9974, 0);
    }

    #[test]
    fun test_share_matches_exact_value_for_upper_half_overlap() {
        let share = pool::calculate_position_share(
            i32::neg_from(100),
            i32::from(100),
            LIQUIDITY,
            Q64,
            i32::zero(),
            i32::from(100),
        );

        assert!(share == 4987, 0);
    }

    #[test]
    fun test_add_liquidity_amounts_keep_distinct_desired_and_min_values() {
        let (desired_a, desired_b, min_a, min_b) = pool::add_liquidity_amounts_for_test(
            Q64,
            i32::neg_from(100),
            i32::from(100),
            LIQUIDITY,
        );

        assert!(min_a > 0, 0);
        assert!(min_b > 0, 0);
        assert!(desired_a == min_a + 1, 0);
        assert!(desired_b == min_b + 1, 0);
    }

    #[test]
    fun test_add_liquidity_amounts_do_not_round_zero_side() {
        let (desired_a, desired_b, min_a, min_b) = pool::add_liquidity_amounts_for_test(
            Q64,
            i32::from(50),
            i32::from(100),
            LIQUIDITY,
        );

        assert!(min_a > 0, 0);
        assert!(desired_a == min_a + 1, 0);
        assert!(min_b == 0, 0);
        assert!(desired_b == 0, 0);
    }

    #[test]
    fun test_add_liquidity_min_amount_accepts_equal_desired_amount() {
        pool::check_add_liquidity_amount_limits_for_test(100, 200, 100, 200);
    }

    #[test]
    #[expected_failure(abort_code = 1, location = turbos_farming::pool)]
    fun test_add_liquidity_min_amount_rejects_desired_below_minimum() {
        pool::check_add_liquidity_amount_limits_for_test(100, 200, 99, 200);
    }

    #[test]
    fun test_fix_coin_add_liquidity_accepts_one_sided_amount() {
        pool::assert_fix_coin_amount_non_zero_for_testing(100, 0);
        pool::assert_fix_coin_amount_non_zero_for_testing(0, 100);
    }

    #[test]
    #[expected_failure(abort_code = 13, location = turbos_farming::pool)]
    fun test_fix_coin_add_liquidity_rejects_zero_amounts() {
        pool::assert_fix_coin_amount_non_zero_for_testing(0, 0);
    }

    #[test]
    fun test_position_reward_amount_preserves_high_precision_accumulator() {
        let reward = pool::position_reward_amount_for_testing(
            10000000000000000000000000000,
            1000000000,
        );

        assert!(reward == 10, 0);
    }

    #[test]
    fun test_effective_range_accepts_tick_inside_bounds() {
        pool::check_effective_range(
            i32::neg_from(100),
            i32::from(100),
            Q64,
            1,
        );
    }

    #[test]
    fun test_effective_range_migration_lock_defaults_to_clear() {
        let ctx = &mut tx_context::dummy();
        let farming_pool = pool::new_pool_for_testing(
            new_id(ctx),
            i32::neg_from(100),
            i32::from(100),
            Q64,
            ctx,
        );

        assert!(!pool::is_effective_range_migrating(&farming_pool), 0);
        pool::assert_not_effective_range_migrating_for_testing(&farming_pool);

        transfer::public_transfer(farming_pool, USER);
    }

    #[test]
    fun test_effective_range_migration_lock_can_be_cleared() {
        let ctx = &mut tx_context::dummy();
        let mut farming_pool = pool::new_pool_for_testing(
            new_id(ctx),
            i32::neg_from(100),
            i32::from(100),
            Q64,
            ctx,
        );

        pool::set_effective_range_migrating_for_testing(&mut farming_pool, true);
        assert!(pool::is_effective_range_migrating(&farming_pool), 0);
        pool::set_effective_range_migrating_for_testing(&mut farming_pool, false);
        pool::assert_not_effective_range_migrating_for_testing(&farming_pool);

        transfer::public_transfer(farming_pool, USER);
    }

    #[test]
    #[expected_failure(abort_code = 16, location = turbos_farming::pool)]
    fun test_effective_range_migration_lock_blocks_user_actions() {
        let ctx = &mut tx_context::dummy();
        let mut farming_pool = pool::new_pool_for_testing(
            new_id(ctx),
            i32::neg_from(100),
            i32::from(100),
            Q64,
            ctx,
        );

        pool::set_effective_range_migrating_for_testing(&mut farming_pool, true);
        pool::assert_not_effective_range_migrating_for_testing(&farming_pool);

        transfer::public_transfer(farming_pool, USER);
    }

    #[test]
    #[expected_failure(abort_code = 5, location = turbos_farming::pool)]
    fun test_effective_range_rejects_tick_outside_bounds() {
        pool::check_effective_range(
            i32::from(10),
            i32::from(100),
            Q64,
            1,
        );
    }

    #[test]
    #[expected_failure(abort_code = 10, location = turbos_farming::pool)]
    fun test_share_rejects_invalid_position_tick_range() {
        pool::calculate_position_share(
            i32::from(100),
            i32::from(100),
            LIQUIDITY,
            Q64,
            i32::neg_from(100),
            i32::from(100),
        );
    }
}
