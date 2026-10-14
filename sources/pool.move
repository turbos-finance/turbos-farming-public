module turbos_farming::pool {
    use turbos_farming::{
        config::{Self, GlobalConfig},
        rewarder::{Self, RewarderManager}
    };
    use std::{string::{String, utf8}, type_name::{Self, TypeName}};
    use sui::{
        balance::{Self, Balance},
        clock::Clock,
        coin::{Self, Coin},
        dynamic_object_field as dof,
        event::emit,
        linked_table::{Self, LinkedTable},
        vec_map::{Self, VecMap}
    };
    use turbos_clmm::{
        full_math_u128,
        i32::{Self, I32},
        math_liquidity,
        math_tick,
        pool::{Self as clmm_pool, Pool as CLMMPool, PoolRewardVault, Versioned},
        position_manager::Positions,
        position_nft::{Self, TurbosPositionNFT}
    };

    const ACC_PRECISION: u256 = 1000000000000000000000000000000000000;
    const EInvalidClmmPoolId: u64 = 1;
    const EPoolPositionNotMatch: u64 = 2;
    const EPoolCLmmPoolNotMatch: u64 = 3;
    const ERewarderNotHarvested: u64 = 4;
    const EEffectiveRangeError: u64 = 5;
    const ERewarderNotExists: u64 = 6;
    const ERewarderAlreadyExists: u64 = 7;
    const EPoolHasNoRewarder: u64 = 8;
    const EStartError: u64 = 9;
    const EInvalidTickRange: u64 = 10;
    const EPoolConfigNotExists: u64 = 11;
    const EPoolConfigAlreadyExists: u64 = 12;
    const EPositionLiquidityInvalid: u64 = 13;
    const EPositionNotExists: u64 = 14;
    const EMigrateLimitInvalid: u64 = 15;
    const EEffectiveRangeMigrating: u64 = 16;

    public struct POOL has drop {}

    public struct WrappedPositionNFT has key, store {
        id: UID,
        pool_id: ID,
        nft: TurbosPositionNFT,
        url: String,
    }

    public struct PositionRewardInfo has copy, drop, store {
        reward: u128,
        reward_debt: u128,
        reward_harvested: u64,
    }

    public struct WrappedPositionInfo has store {
        id: ID,
        pool_id: ID,
        clmm_pool_id: ID,
        nft_id: ID,
        nft_address: address,
        tick_lower: I32,
        tick_upper: I32,
        liquidity: u128,
        effective_tick_lower: I32,
        effective_tick_upper: I32,
        sqrt_price: u128,
        share: u128,
        rewards: VecMap<TypeName, PositionRewardInfo>,
    }

    public struct Pool has key, store {
        id: UID,
        clmm_pool_id: ID,
        effective_tick_lower: I32,
        effective_tick_upper: I32,
        sqrt_price: u128,
        total_share: u128,
        rewarders: vector<TypeName>,
        positions: LinkedTable<ID, WrappedPositionInfo>,
        is_effective_range_migrating: bool,
    }

    public struct PoolInvalidPositions has key, store {
        id: UID,
        positions: LinkedTable<ID, WrappedPositionInfo>,
    }

    public struct CreatePoolEvent has copy, drop {
        pool_id: ID,
        clmm_pool_id: ID,
        sqrt_price: u128,
        effective_tick_lower: I32,
        effective_tick_upper: I32,
    }
    public struct UpdateEffectiveTickRangeEvent has copy, drop {
        pool_id: ID,
        clmm_pool_id: ID,
        effective_tick_lower: I32,
        effective_tick_upper: I32,
        sqrt_price: u128,
        start: vector<ID>,
        end: Option<ID>,
        limit: u64,
    }
    public struct AddRewardEvent has copy, drop {
        pool_id: ID,
        clmm_pool_id: ID,
        rewarder: TypeName,
        allocate_point: u64,
    }
    public struct UpdatePoolAllocatePointEvent has copy, drop {
        pool_id: ID,
        clmm_pool_id: ID,
        old_allocate_point: u64,
        new_allocate_point: u64,
    }
    public struct DepositEvent has copy, drop {
        pool_id: ID,
        wrapped_position_id: ID,
        clmm_pool_id: ID,
        nft_id: ID,
        effective_tick_lower: I32,
        effective_tick_upper: I32,
        sqrt_price: u128,
        liquidity: u128,
        share: u128,
        pool_total_share: u128,
    }
    public struct WithdrawEvent has copy, drop {
        pool_id: ID,
        wrapped_position_id: ID,
        clmm_pool_id: ID,
        nft_id: ID,
        share: u128,
    }
    public struct HarvestEvent has copy, drop {
        pool_id: ID,
        wrapped_position_id: ID,
        clmm_pool_id: ID,
        nft_id: ID,
        rewarder_type: TypeName,
        amount: u64,
    }
    public struct AccumulatedPositionRewardsEvent has copy, drop {
        pool_id: ID,
        wrapped_position_id: ID,
        nft_id: ID,
        rewards: VecMap<TypeName, u64>,
    }
    public struct AddLiquidityEvent has copy, drop {
        pool_id: ID,
        wrapped_position_id: ID,
        clmm_pool_id: ID,
        nft_id: ID,
        effective_tick_lower: I32,
        effective_tick_upper: I32,
        sqrt_price: u128,
        old_liquidity: u128,
        new_liquidity: u128,
        old_share: u128,
        new_share: u128,
    }
    public struct AddLiquidityFixCoinEvent has copy, drop {
        pool_id: ID,
        wrapped_position_id: ID,
        clmm_pool_id: ID,
        nft_id: ID,
        effective_tick_lower: I32,
        effective_tick_upper: I32,
        sqrt_price: u128,
        old_liquidity: u128,
        new_liquidity: u128,
        old_share: u128,
        new_share: u128,
    }
    public struct RemoveLiquidityEvent has copy, drop {
        pool_id: ID,
        wrapped_position_id: ID,
        clmm_pool_id: ID,
        nft_id: ID,
        effective_tick_lower: I32,
        effective_tick_upper: I32,
        sqrt_price: u128,
        old_liquidity: u128,
        new_liquidity: u128,
        old_share: u128,
        new_share: u128,
    }
    public struct CollectFeeEvent has copy, drop {
        wrapped_position_id: ID,
        clmm_pool_id: ID,
        nft_id: ID,
        amount_a: u64,
        amount_b: u64,
    }
    public struct ClosePositionEvent has copy, drop {
        pool_id: ID,
        wrapped_position_id: ID,
        clmm_pool_id: ID,
        nft_id: ID,
        liquidity: u128,
        amount_a: u64,
        amount_b: u64,
    }
    public struct MigrateInvalidPoolPositionsEvent has copy, drop {
        pool_id: ID,
        clmm_pool_id: ID,
        start_idx: Option<ID>,
        end: Option<ID>,
    }

    // ==================== Public Functions ====================

    public fun accumulated_position_rewards(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        wrapped_position_id: ID,
        clk: &Clock,
    ) {
        config::checked_package_version(global_config);
        assert_not_effective_range_migrating(pool);
        assert!(
            linked_table::contains<ID, WrappedPositionInfo>(&pool.positions, wrapped_position_id),
            EPositionNotExists,
        );
        let pool_id = object::id<Pool>(pool);
        let rewarders = pool.rewarders;
        let clmm_pool_id = pool.clmm_pool_id;
        let info = linked_table::borrow_mut<ID, WrappedPositionInfo>(
            &mut pool.positions,
            wrapped_position_id,
        );
        let old_share = info.share;
        update_position_share(
            info,
            rewarder::pool_rewards_settle(rewarder_manager, rewarders, clmm_pool_id, clk),
            old_share,
        );
        let mut idx = 0;
        let mut rewards_out = vec_map::empty<TypeName, u64>();
        while (idx < vec_map::length<TypeName, PositionRewardInfo>(&info.rewards)) {
            let (reward_type, reward_info) = vec_map::get_entry_by_idx<
                TypeName,
                PositionRewardInfo,
            >(&info.rewards, idx);
            vec_map::insert<TypeName, u64>(
                &mut rewards_out,
                *reward_type,
                (reward_info.reward as u64),
            );
            idx = idx + 1;
        };
        emit(AccumulatedPositionRewardsEvent {
            pool_id,
            wrapped_position_id,
            nft_id: info.nft_id,
            rewards: rewards_out,
        });
    }

    public fun add_liquidity<CoinA, CoinB, FeeType>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        clmm_pool: &mut CLMMPool<CoinA, CoinB, FeeType>,
        positions: &mut Positions,
        versioned: &Versioned,
        wrapped_position: &mut WrappedPositionNFT,
        coin_a: Coin<CoinA>,
        coin_b: Coin<CoinB>,
        amount_limit_a: u64,
        amount_limit_b: u64,
        delta_liquidity: u128,
        clk: &Clock,
        deadline: u64,
        ctx: &mut TxContext,
    ): (Balance<CoinA>, Balance<CoinB>) {
        config::checked_package_version(global_config);
        assert_not_effective_range_migrating(pool);
        assert!(object::id<Pool>(pool) == wrapped_position.pool_id, EPoolPositionNotMatch);
        assert!(
            pool.clmm_pool_id == object::id<CLMMPool<CoinA, CoinB, FeeType>>(clmm_pool),
            EPoolCLmmPoolNotMatch,
        );
        let wrapped_id = object::id<WrappedPositionNFT>(wrapped_position);
        assert!(
            linked_table::contains<ID, WrappedPositionInfo>(&pool.positions, wrapped_id),
            EPositionNotExists,
        );
        let (nft_address, nft_id, tick_lower, tick_upper, old_liquidity, old_share) = {
            let info = linked_table::borrow<ID, WrappedPositionInfo>(&pool.positions, wrapped_id);
            (
                info.nft_address,
                info.nft_id,
                info.tick_lower,
                info.tick_upper,
                info.liquidity,
                info.share,
            )
        };
        assert!(delta_liquidity > 0, EPositionLiquidityInvalid);
        let cur_sqrt = clmm_pool::get_pool_sqrt_price<CoinA, CoinB, FeeType>(clmm_pool);
        let sqrt_a = math_tick::sqrt_price_from_tick_index(tick_lower);
        let sqrt_b = math_tick::sqrt_price_from_tick_index(tick_upper);
        let (need_a_u128, need_b_u128) = math_liquidity::get_amount_for_liquidity(
            cur_sqrt,
            sqrt_a,
            sqrt_b,
            delta_liquidity,
        );
        let desired_a_u128 = amount_desired_for_requested_liquidity(need_a_u128);
        let desired_b_u128 = amount_desired_for_requested_liquidity(need_b_u128);
        let desired_a = desired_a_u128 as u64;
        let desired_b = desired_b_u128 as u64;
        let (
            coin_a_left,
            coin_b_left,
        ) = turbos_clmm::position_manager::increase_liquidity_with_return_<CoinA, CoinB, FeeType>(
            clmm_pool,
            positions,
            vector::singleton(coin_a),
            vector::singleton(coin_b),
            &mut wrapped_position.nft,
            desired_a,
            desired_b,
            amount_limit_a,
            amount_limit_b,
            deadline,
            clk,
            versioned,
            ctx,
        );
        let (_, _, new_liquidity) = turbos_clmm::position_manager::get_position_info(
            positions,
            nft_address,
        );
        assert!(new_liquidity > old_liquidity, EPositionLiquidityInvalid);
        let new_share = update_position_liquidity(
            rewarder_manager,
            pool,
            wrapped_position,
            new_liquidity,
            clk,
        );
        emit(AddLiquidityEvent {
            pool_id: object::id<Pool>(pool),
            wrapped_position_id: wrapped_id,
            clmm_pool_id: pool.clmm_pool_id,
            nft_id,
            effective_tick_lower: pool.effective_tick_lower,
            effective_tick_upper: pool.effective_tick_upper,
            sqrt_price: pool.sqrt_price,
            old_liquidity,
            new_liquidity,
            old_share,
            new_share,
        });
        (coin::into_balance<CoinA>(coin_a_left), coin::into_balance<CoinB>(coin_b_left))
    }

    fun amount_desired_for_requested_liquidity(amount_floor: u128): u128 {
        // CLMM derives liquidity from desired amounts with floor rounding. The farming
        // math above also returns floor token amounts for a requested liquidity delta,
        // so a non-zero side needs one extra unit to avoid deriving less liquidity.
        let amount = amount_floor;
        if (amount == 0) return 0;
        amount + 1
    }

    #[test_only]
    public fun add_liquidity_amounts_for_test(
        sqrt_price: u128,
        tick_lower: I32,
        tick_upper: I32,
        delta_liquidity: u128,
    ): (u64, u64, u64, u64) {
        let sqrt_a = math_tick::sqrt_price_from_tick_index(tick_lower);
        let sqrt_b = math_tick::sqrt_price_from_tick_index(tick_upper);
        let (need_a_u128, need_b_u128) = math_liquidity::get_amount_for_liquidity(
            sqrt_price,
            sqrt_a,
            sqrt_b,
            delta_liquidity,
        );
        let desired_a_u128 = amount_desired_for_requested_liquidity(need_a_u128);
        let desired_b_u128 = amount_desired_for_requested_liquidity(need_b_u128);
        (
            desired_a_u128 as u64,
            desired_b_u128 as u64,
            need_a_u128 as u64,
            need_b_u128 as u64,
        )
    }

    #[test_only]
    public fun check_add_liquidity_amount_limits_for_test(
        min_amount_a: u64,
        min_amount_b: u64,
        desired_a: u64,
        desired_b: u64,
    ) {
        assert!((desired_a as u128) >= (min_amount_a as u128), 1);
        assert!((desired_b as u128) >= (min_amount_b as u128), 1);
    }

    public fun add_liquidity_fix_coin<CoinA, CoinB, FeeType>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        clmm_pool: &mut CLMMPool<CoinA, CoinB, FeeType>,
        positions: &mut Positions,
        versioned: &Versioned,
        wrapped_position: &mut WrappedPositionNFT,
        coin_a: Coin<CoinA>,
        coin_b: Coin<CoinB>,
        amount_a: u64,
        amount_b: u64,
        fix_amount_a: bool,
        clk: &Clock,
        deadline: u64,
        ctx: &mut TxContext,
    ): (Balance<CoinA>, Balance<CoinB>) {
        config::checked_package_version(global_config);
        assert_not_effective_range_migrating(pool);
        assert!(object::id<Pool>(pool) == wrapped_position.pool_id, EPoolPositionNotMatch);
        assert!(
            pool.clmm_pool_id == object::id<CLMMPool<CoinA, CoinB, FeeType>>(clmm_pool),
            EPoolCLmmPoolNotMatch,
        );
        let wrapped_id = object::id<WrappedPositionNFT>(wrapped_position);
        assert!(
            linked_table::contains<ID, WrappedPositionInfo>(&pool.positions, wrapped_id),
            EPositionNotExists,
        );
        let (nft_address, nft_id, old_liquidity, old_share) = {
            let info = linked_table::borrow<ID, WrappedPositionInfo>(&pool.positions, wrapped_id);
            (info.nft_address, info.nft_id, info.liquidity, info.share)
        };
        assert!(amount_a > 0 || amount_b > 0, EPositionLiquidityInvalid);
        let (min_a, min_b) = if (fix_amount_a) { (amount_a, 0) } else { (0, amount_b) };
        let (
            coin_a_left,
            coin_b_left,
        ) = turbos_clmm::position_manager::increase_liquidity_with_return_<CoinA, CoinB, FeeType>(
            clmm_pool,
            positions,
            vector::singleton(coin_a),
            vector::singleton(coin_b),
            &mut wrapped_position.nft,
            amount_a,
            amount_b,
            min_a,
            min_b,
            deadline,
            clk,
            versioned,
            ctx,
        );
        let (_, _, new_liquidity) = turbos_clmm::position_manager::get_position_info(
            positions,
            nft_address,
        );
        assert!(new_liquidity > old_liquidity, EPositionLiquidityInvalid);
        let new_share = update_position_liquidity(
            rewarder_manager,
            pool,
            wrapped_position,
            new_liquidity,
            clk,
        );
        emit(AddLiquidityFixCoinEvent {
            pool_id: object::id<Pool>(pool),
            wrapped_position_id: wrapped_id,
            clmm_pool_id: pool.clmm_pool_id,
            nft_id,
            effective_tick_lower: pool.effective_tick_lower,
            effective_tick_upper: pool.effective_tick_upper,
            sqrt_price: pool.sqrt_price,
            old_liquidity,
            new_liquidity,
            old_share,
            new_share,
        });
        (coin::into_balance<CoinA>(coin_a_left), coin::into_balance<CoinB>(coin_b_left))
    }

    public fun add_rewarder<RewarderCoin>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        allocate_point: u64,
        clk: &Clock,
        ctx: &TxContext,
    ) {
        config::checked_package_version(global_config);
        config::check_pool_manager_role(global_config, tx_context::sender(ctx));
        let rewarder_type = type_name::with_defining_ids<RewarderCoin>();
        assert!(
            !vector::contains<TypeName>(&pool.rewarders, &rewarder_type),
            ERewarderAlreadyExists,
        );
        rewarder::add_pool<RewarderCoin>(
            rewarder_manager,
            pool.clmm_pool_id,
            allocate_point,
            clk,
        );
        vector::push_back<TypeName>(&mut pool.rewarders, rewarder_type);
        emit(AddRewardEvent {
            pool_id: object::id<Pool>(pool),
            clmm_pool_id: pool.clmm_pool_id,
            rewarder: rewarder_type,
            allocate_point,
        });
    }

    fun assert_position_liquidity_valid(
        sqrt_price: u128,
        tick_lower: I32,
        tick_upper: I32,
        liquidity: u128,
    ) {
        let sqrt_a = math_tick::sqrt_price_from_tick_index(tick_lower);
        let sqrt_b = math_tick::sqrt_price_from_tick_index(tick_upper);
        let (am_a, am_b) = math_liquidity::get_amount_for_liquidity(
            sqrt_price,
            sqrt_a,
            sqrt_b,
            liquidity,
        );
        assert!(am_a > 0 || am_b > 0, EPositionLiquidityInvalid);
    }

    fun assert_not_effective_range_migrating(pool: &Pool) {
        assert!(!pool.is_effective_range_migrating, EEffectiveRangeMigrating);
    }

    public fun borrow_position_nft(wp: &WrappedPositionNFT): &TurbosPositionNFT { &wp.nft }

    public fun borrow_pool_rewarders(pool: &Pool): &vector<TypeName> { &pool.rewarders }

    public fun borrow_position_rewarder_info(
        info: &WrappedPositionInfo,
        rewarder_type: &TypeName,
    ): &PositionRewardInfo {
        vec_map::get<TypeName, PositionRewardInfo>(&info.rewards, rewarder_type)
    }

    public fun borrow_rewarders(info: &WrappedPositionInfo): &VecMap<TypeName, PositionRewardInfo> {
        &info.rewards
    }

    public fun borrow_wrapped_position_info(pool: &Pool, id: ID): &WrappedPositionInfo {
        linked_table::borrow<ID, WrappedPositionInfo>(&pool.positions, id)
    }

    public fun calculate_position_share(
        tick_lower: I32,
        tick_upper: I32,
        liquidity: u128,
        sqrt_price: u128,
        effective_tick_lower: I32,
        effective_tick_upper: I32,
    ): u128 {
        assert!(i32::lt(tick_lower, tick_upper), EInvalidTickRange);
        assert!(i32::lt(effective_tick_lower, effective_tick_upper), EInvalidTickRange);
        if (
            i32::lte(tick_upper, effective_tick_lower) || i32::gte(tick_lower, effective_tick_upper)
        ) return 0;
        let lo = if (i32::lt(tick_lower, effective_tick_lower)) effective_tick_lower
        else tick_lower;
        let hi = if (i32::lt(tick_upper, effective_tick_upper)) tick_upper
        else effective_tick_upper;
        let sa = math_tick::sqrt_price_from_tick_index(lo);
        let sb = math_tick::sqrt_price_from_tick_index(hi);
        let (am_a, am_b) = math_liquidity::get_amount_for_liquidity(sqrt_price, sa, sb, liquidity);
        (((am_a as u256) * full_math_u128::full_mul(sqrt_price, sqrt_price) >> 128) as u128) + (am_b as u128)
    }

    public fun check_effective_range(
        eff_lower: I32,
        eff_upper: I32,
        sqrt_price: u128,
        tick_spacing: u32,
    ) {
        assert!(i32::lt(eff_lower, eff_upper), EEffectiveRangeError);
        assert!(
            i32::gte(eff_lower, math_tick::get_min_tick(tick_spacing)) && i32::lte(eff_upper, math_tick::get_max_tick(tick_spacing)),
            EEffectiveRangeError,
        );
        let tick = math_tick::tick_index_from_sqrt_price(sqrt_price);
        assert!(i32::lt(eff_lower, tick) && i32::gt(eff_upper, tick), EEffectiveRangeError);
    }

    public fun clmm_pool_id(pool: &Pool): ID { pool.clmm_pool_id }

    public fun close_position<CoinA, CoinB, FeeType>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        clmm_pool: &mut CLMMPool<CoinA, CoinB, FeeType>,
        positions: &mut Positions,
        versioned: &Versioned,
        wrapped_position: WrappedPositionNFT,
        min_amount_a: u64,
        min_amount_b: u64,
        clk: &Clock,
        ctx: &mut TxContext,
    ): (Balance<CoinA>, Balance<CoinB>) {
        config::checked_package_version(global_config);
        assert_not_effective_range_migrating(pool);
        assert!(
            pool.clmm_pool_id == object::id<CLMMPool<CoinA, CoinB, FeeType>>(clmm_pool),
            EPoolCLmmPoolNotMatch,
        );
        let pool_id = object::id<Pool>(pool);
        let wrapped_position_id = object::id<WrappedPositionNFT>(&wrapped_position);
        let mut nft = withdraw(global_config, rewarder_manager, pool, wrapped_position, clk);
        let nft_addr = object::id_address(&nft);
        let nft_id = position_nft::position_id(&nft);
        let (
            _pos_tick_lower,
            _pos_tick_upper,
            pos_liquidity,
        ) = turbos_clmm::position_manager::get_position_info(positions, nft_addr);
        let (mut ba, mut bb) = if (pos_liquidity > 0) {
            let (ca, cb) = turbos_clmm::position_manager::decrease_liquidity_with_return_<
                CoinA,
                CoinB,
                FeeType,
            >(
                clmm_pool,
                positions,
                &mut nft,
                pos_liquidity,
                min_amount_a,
                min_amount_b,
                clk.timestamp_ms() + 60000,
                clk,
                versioned,
                ctx,
            );
            (coin::into_balance<CoinA>(ca), coin::into_balance<CoinB>(cb))
        } else { (balance::zero<CoinA>(), balance::zero<CoinB>()) };
        let (fee_a, fee_b) = turbos_clmm::position_manager::collect_with_return_<
            CoinA,
            CoinB,
            FeeType,
        >(
            clmm_pool,
            positions,
            &mut nft,
            0xFFFFFFFFFFFFFFFF,
            0xFFFFFFFFFFFFFFFF,
            nft_addr,
            clk.timestamp_ms() + 60000,
            clk,
            versioned,
            ctx,
        );
        balance::join<CoinA>(&mut ba, coin::into_balance<CoinA>(fee_a));
        balance::join<CoinB>(&mut bb, coin::into_balance<CoinB>(fee_b));
        turbos_clmm::position_manager::burn<CoinA, CoinB, FeeType>(
            positions,
            nft,
            versioned,
            ctx,
        );
        emit(ClosePositionEvent {
            pool_id,
            wrapped_position_id,
            clmm_pool_id: object::id<CLMMPool<CoinA, CoinB, FeeType>>(clmm_pool),
            nft_id,
            liquidity: pos_liquidity,
            amount_a: balance::value<CoinA>(&ba),
            amount_b: balance::value<CoinB>(&bb),
        });
        (ba, bb)
    }

    public fun collect_clmm_reward<RewardCoin, CoinA, CoinB, FeeType>(
        global_config: &GlobalConfig,
        clmm_pool: &mut CLMMPool<CoinA, CoinB, FeeType>,
        positions: &mut Positions,
        versioned: &Versioned,
        wrapped_position: &mut WrappedPositionNFT,
        vault: &mut PoolRewardVault<RewardCoin>,
        reward_index: u64,
        mut reward_coin: Coin<RewardCoin>,
        clk: &Clock,
        ctx: &mut TxContext,
    ): Balance<RewardCoin> {
        config::checked_package_version(global_config);
        assert!(
            object::id<CLMMPool<CoinA, CoinB, FeeType>>(clmm_pool) == position_nft::pool_id(&wrapped_position.nft),
            EInvalidClmmPoolId,
        );
        let nft_id = object::id_address(&wrapped_position.nft);
        let collected = turbos_clmm::position_manager::collect_reward_with_return_<
            CoinA,
            CoinB,
            FeeType,
            RewardCoin,
        >(
            clmm_pool,
            positions,
            &mut wrapped_position.nft,
            vault,
            reward_index,
            0xFFFFFFFFFFFFFFFF,
            nft_id,
            clk.timestamp_ms() + 60000,
            clk,
            versioned,
            ctx,
        );
        coin::join<RewardCoin>(&mut reward_coin, collected);
        coin::into_balance<RewardCoin>(reward_coin)
    }

    public fun collect_fee<CoinA, CoinB, FeeType>(
        global_config: &GlobalConfig,
        clmm_pool: &mut CLMMPool<CoinA, CoinB, FeeType>,
        positions: &mut Positions,
        versioned: &Versioned,
        wrapped_position: &mut WrappedPositionNFT,
        clk: &Clock,
        ctx: &mut TxContext,
    ): (Balance<CoinA>, Balance<CoinB>) {
        config::checked_package_version(global_config);
        assert!(
            object::id<CLMMPool<CoinA, CoinB, FeeType>>(clmm_pool) == position_nft::pool_id(&wrapped_position.nft),
            EInvalidClmmPoolId,
        );
        let nft_id = object::id_address(&wrapped_position.nft);
        let (ca, cb) = turbos_clmm::position_manager::collect_with_return_<CoinA, CoinB, FeeType>(
            clmm_pool,
            positions,
            &mut wrapped_position.nft,
            0xFFFFFFFFFFFFFFFF,
            0xFFFFFFFFFFFFFFFF,
            nft_id,
            clk.timestamp_ms() + 60000,
            clk,
            versioned,
            ctx,
        );
        let ba = coin::into_balance<CoinA>(ca);
        let bb = coin::into_balance<CoinB>(cb);
        emit(CollectFeeEvent {
            wrapped_position_id: object::id<WrappedPositionNFT>(wrapped_position),
            clmm_pool_id: object::id<CLMMPool<CoinA, CoinB, FeeType>>(clmm_pool),
            nft_id: position_nft::position_id(&wrapped_position.nft),
            amount_a: balance::value<CoinA>(&ba),
            amount_b: balance::value<CoinB>(&bb),
        });
        (ba, bb)
    }

    public fun create_pool<CoinA, CoinB, FeeType>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        clmm_pool: &CLMMPool<CoinA, CoinB, FeeType>,
        effective_tick_lower: I32,
        effective_tick_upper: I32,
        _sqrt_price: u128,
        ctx: &mut TxContext,
    ) {
        config::checked_package_version(global_config);
        config::check_pool_manager_role(global_config, tx_context::sender(ctx));
        let sqrt_price = clmm_pool::get_pool_sqrt_price<CoinA, CoinB, FeeType>(clmm_pool);
        check_effective_range(
            effective_tick_lower,
            effective_tick_upper,
            sqrt_price,
            clmm_pool::get_pool_tick_spacing<CoinA, CoinB, FeeType>(clmm_pool),
        );
        let pool = Pool {
            id: object::new(ctx),
            clmm_pool_id: object::id<CLMMPool<CoinA, CoinB, FeeType>>(clmm_pool),
            effective_tick_lower,
            effective_tick_upper,
            sqrt_price,
            total_share: 0,
            rewarders: vector::empty<TypeName>(),
            positions: linked_table::new<ID, WrappedPositionInfo>(ctx),
            is_effective_range_migrating: false,
        };
        let pid = object::id<Pool>(&pool);
        rewarder::register_pool(
            rewarder_manager,
            object::id<CLMMPool<CoinA, CoinB, FeeType>>(clmm_pool),
        );
        transfer::share_object<Pool>(pool);
        emit(CreatePoolEvent {
            pool_id: pid,
            clmm_pool_id: object::id<CLMMPool<CoinA, CoinB, FeeType>>(clmm_pool),
            sqrt_price,
            effective_tick_lower,
            effective_tick_upper,
        });
    }

    public fun deposit<CoinA, CoinB, FeeType>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        clmm_pool: &CLMMPool<CoinA, CoinB, FeeType>,
        positions: &Positions,
        nft: TurbosPositionNFT,
        clk: &Clock,
        ctx: &mut TxContext,
    ): WrappedPositionNFT {
        config::checked_package_version(global_config);
        assert_not_effective_range_migrating(pool);
        assert!(position_nft::pool_id(&nft) == pool.clmm_pool_id, EPoolPositionNotMatch);
        assert!(
            pool.clmm_pool_id == object::id<CLMMPool<CoinA, CoinB, FeeType>>(clmm_pool),
            EPoolCLmmPoolNotMatch,
        );
        assert!(vector::length<TypeName>(&pool.rewarders) > 0, EPoolHasNoRewarder);
        let nft_id = position_nft::position_id(&nft);
        let nft_addr = object::id_address(&nft);
        let (tick_lower, tick_upper, liquidity) = turbos_clmm::position_manager::get_position_info(
            positions,
            nft_addr,
        );
        let url = utf8(b"");
        assert_position_liquidity_valid(
            clmm_pool::get_pool_sqrt_price<CoinA, CoinB, FeeType>(clmm_pool),
            tick_lower,
            tick_upper,
            liquidity,
        );
        let wrapped = WrappedPositionNFT {
            id: object::new(ctx),
            pool_id: object::id<Pool>(pool),
            nft,
            url,
        };
        let wrapped_info = WrappedPositionInfo {
            id: object::id<WrappedPositionNFT>(&wrapped),
            pool_id: object::id<Pool>(pool),
            clmm_pool_id: pool.clmm_pool_id,
            nft_id,
            nft_address: nft_addr,
            tick_lower,
            tick_upper,
            liquidity,
            effective_tick_lower: pool.effective_tick_lower,
            effective_tick_upper: pool.effective_tick_upper,
            sqrt_price: pool.sqrt_price,
            share: 0,
            rewards: vec_map::empty<TypeName, PositionRewardInfo>(),
        };
        linked_table::push_back<ID, WrappedPositionInfo>(
            &mut pool.positions,
            object::id<WrappedPositionNFT>(&wrapped),
            wrapped_info,
        );
        let new_share = update_position_liquidity(rewarder_manager, pool, &wrapped, liquidity, clk);
        emit(DepositEvent {
            pool_id: object::id<Pool>(pool),
            wrapped_position_id: object::id<WrappedPositionNFT>(&wrapped),
            clmm_pool_id: pool.clmm_pool_id,
            nft_id,
            effective_tick_lower: pool.effective_tick_lower,
            effective_tick_upper: pool.effective_tick_upper,
            sqrt_price: pool.sqrt_price,
            liquidity,
            share: new_share,
            pool_total_share: pool.total_share,
        });
        wrapped
    }

    fun destroy_wrapping_position_info(info: WrappedPositionInfo) {
        let WrappedPositionInfo {
            id: _,
            pool_id: _,
            clmm_pool_id: _,
            nft_id: _,
            nft_address: _,
            tick_lower: _,
            tick_upper: _,
            liquidity: _,
            effective_tick_lower: _,
            effective_tick_upper: _,
            sqrt_price: _,
            share: _,
            rewards: r,
        } = info;
        let mut remaining = r;
        while (!vec_map::is_empty<TypeName, PositionRewardInfo>(&remaining)) {
            let (_, _) = vec_map::pop<TypeName, PositionRewardInfo>(&mut remaining);
        };
        vec_map::destroy_empty<TypeName, PositionRewardInfo>(remaining);
    }

    public fun effective_tick_lower(pool: &Pool): I32 { pool.effective_tick_lower }

    public fun effective_tick_upper(pool: &Pool): I32 { pool.effective_tick_upper }

    public fun harvest<RewardCoin>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        wrapped_position: &mut WrappedPositionNFT,
        clk: &Clock,
    ): Balance<RewardCoin> {
        config::checked_package_version(global_config);
        assert_not_effective_range_migrating(pool);
        let rewarder_type = type_name::with_defining_ids<RewardCoin>();
        let pool_id = object::id<Pool>(pool);
        assert!(pool_id == wrapped_position.pool_id, EPoolPositionNotMatch);
        assert!(vector::contains<TypeName>(&pool.rewarders, &rewarder_type), ERewarderNotExists);
        let wrapped_id = object::id<WrappedPositionNFT>(wrapped_position);
        if (!linked_table::contains<ID, WrappedPositionInfo>(&pool.positions, wrapped_id)) {
            let inv = dof::borrow_mut<String, PoolInvalidPositions>(
                &mut pool.id,
                utf8(b"invalid_pool_positions"),
            );
            let info = linked_table::borrow_mut<ID, WrappedPositionInfo>(
                &mut inv.positions,
                wrapped_id,
            );
            let ri = vec_map::get_mut<TypeName, PositionRewardInfo>(
                &mut info.rewards,
                &rewarder_type,
            );
            let amt = (ri.reward as u64);
            ri.reward = 0;
            ri.reward_harvested = ri.reward_harvested + amt;
            emit(HarvestEvent {
                pool_id,
                wrapped_position_id: wrapped_id,
                clmm_pool_id: info.clmm_pool_id,
                nft_id: info.nft_id,
                rewarder_type,
                amount: amt,
            });
            return rewarder::withdraw_reward<RewardCoin>(
                    rewarder_manager,
                    position_nft::pool_id(&wrapped_position.nft),
                    amt,
                )
        };
        assert!(
            linked_table::contains<ID, WrappedPositionInfo>(&pool.positions, wrapped_id),
            EPositionNotExists,
        );
        let rewarders = pool.rewarders;
        let clmm_pool_id = pool.clmm_pool_id;
        let info = linked_table::borrow_mut<ID, WrappedPositionInfo>(
            &mut pool.positions,
            wrapped_id,
        );
        let old_share = info.share;
        update_position_share(
            info,
            rewarder::pool_rewards_settle(rewarder_manager, rewarders, clmm_pool_id, clk),
            old_share,
        );
        let ri = vec_map::get_mut<TypeName, PositionRewardInfo>(&mut info.rewards, &rewarder_type);
        let amt = (ri.reward as u64);
        ri.reward = 0;
        ri.reward_harvested = ri.reward_harvested + amt;
        emit(HarvestEvent {
            pool_id,
            wrapped_position_id: wrapped_id,
            clmm_pool_id: info.clmm_pool_id,
            nft_id: info.nft_id,
            rewarder_type,
            amount: amt,
        });
        rewarder::withdraw_reward<RewardCoin>(
            rewarder_manager,
            position_nft::pool_id(&wrapped_position.nft),
            amt,
        )
    }

    fun init(_otw: POOL, _ctx: &mut TxContext) { }

    public fun init_invalid_pool_positions(
        global_config: &GlobalConfig,
        pool: &mut Pool,
        ctx: &mut TxContext,
    ) {
        config::checked_package_version(global_config);
        config::check_pool_manager_role(global_config, tx_context::sender(ctx));
        let inv = PoolInvalidPositions {
            id: object::new(ctx),
            positions: linked_table::new<ID, WrappedPositionInfo>(ctx),
        };
        assert!(
            !dof::exists_<String>(&pool.id, utf8(b"invalid_pool_positions")),
            EPoolConfigAlreadyExists,
        );
        dof::add<String, PoolInvalidPositions>(&mut pool.id, utf8(b"invalid_pool_positions"), inv);
    }

    public fun migrate_invalid_pool_positions<CoinA, CoinB, FeeType>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        clmm_pool: &CLMMPool<CoinA, CoinB, FeeType>,
        start: Option<ID>,
        limit: u64,
        clk: &Clock,
        ctx: &TxContext,
    ) {
        config::checked_package_version(global_config);
        config::check_pool_manager_role(global_config, tx_context::sender(ctx));
        assert!(
            pool.clmm_pool_id == object::id<CLMMPool<CoinA, CoinB, FeeType>>(clmm_pool),
            EPoolCLmmPoolNotMatch,
        );
        assert!(
            dof::exists_<String>(&pool.id, utf8(b"invalid_pool_positions")),
            EPoolConfigNotExists,
        );
        let mut cursor = if (option::is_none<ID>(&start)) {
            *linked_table::front<ID, WrappedPositionInfo>(&pool.positions)
        } else { start };
        if (option::is_none<ID>(&cursor)) return;
        assert!(limit > 0, EMigrateLimitInvalid);
        let mut end_cursor = cursor;
        let cur_price = clmm_pool::get_pool_sqrt_price<CoinA, CoinB, FeeType>(clmm_pool);
        let mut new_ts = pool.total_share;
        let mut ct = 0;
        while (ct < limit && option::is_some<ID>(&cursor)) {
            let pid = *option::borrow<ID>(&cursor);
            let pi = linked_table::borrow<ID, WrappedPositionInfo>(&pool.positions, pid);
            let sa = math_tick::sqrt_price_from_tick_index(pi.tick_lower);
            let sb = math_tick::sqrt_price_from_tick_index(pi.tick_upper);
            let (aa, ab) = math_liquidity::get_amount_for_liquidity(
                cur_price,
                sa,
                sb,
                pi.liquidity,
            );
            cursor = *linked_table::next<ID, WrappedPositionInfo>(&pool.positions, pid);
            end_cursor = cursor;
            if (aa > 0 || ab > 0) { ct = ct + 1; continue };
            let mut ri = linked_table::remove<ID, WrappedPositionInfo>(&mut pool.positions, pid);
            new_ts = new_ts - ri.share;
            update_position_share(
                &mut ri,
                rewarder::pool_rewards_settle(
                    rewarder_manager,
                    pool.rewarders,
                    object::id<CLMMPool<CoinA, CoinB, FeeType>>(clmm_pool),
                    clk,
                ),
                0,
            );
            let inv = dof::borrow_mut<String, PoolInvalidPositions>(
                &mut pool.id,
                utf8(b"invalid_pool_positions"),
            );
            linked_table::push_back<ID, WrappedPositionInfo>(&mut inv.positions, pid, ri);
            ct = ct + 1;
        };
        pool.total_share = new_ts;
        rewarder::set_pool_share(
            rewarder_manager,
            object::id<CLMMPool<CoinA, CoinB, FeeType>>(clmm_pool),
            pool.total_share,
        );
        emit(MigrateInvalidPoolPositionsEvent {
            pool_id: object::id<Pool>(pool),
            clmm_pool_id: object::id<CLMMPool<CoinA, CoinB, FeeType>>(clmm_pool),
            start_idx: start,
            end: end_cursor,
        });
    }

    public fun position_rewarder_info(
        info: &WrappedPositionInfo,
        rewarder_type: &TypeName,
    ): PositionRewardInfo {
        if (!vec_map::contains<TypeName, PositionRewardInfo>(&info.rewards, rewarder_type))
            PositionRewardInfo { reward: 0, reward_debt: 0, reward_harvested: 0 }
        else *vec_map::get<TypeName, PositionRewardInfo>(&info.rewards, rewarder_type)
    }

    public fun remove_liquidity<CoinA, CoinB, FeeType>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        clmm_pool: &mut CLMMPool<CoinA, CoinB, FeeType>,
        positions: &mut Positions,
        versioned: &Versioned,
        wrapped_position: &mut WrappedPositionNFT,
        delta_liquidity: u128,
        min_amount_a: u64,
        min_amount_b: u64,
        clk: &Clock,
        ctx: &mut TxContext,
    ): (Balance<CoinA>, Balance<CoinB>) {
        config::checked_package_version(global_config);
        assert_not_effective_range_migrating(pool);
        assert!(object::id<Pool>(pool) == wrapped_position.pool_id, EPoolPositionNotMatch);
        assert!(
            pool.clmm_pool_id == object::id<CLMMPool<CoinA, CoinB, FeeType>>(clmm_pool),
            EPoolCLmmPoolNotMatch,
        );
        let wrapped_id = object::id<WrappedPositionNFT>(wrapped_position);
        assert!(
            linked_table::contains<ID, WrappedPositionInfo>(&pool.positions, wrapped_id),
            EPositionNotExists,
        );
        let (nft_address, nft_id, tick_lower, tick_upper, old_liquidity, old_share) = {
            let info = linked_table::borrow<ID, WrappedPositionInfo>(&pool.positions, wrapped_id);
            (
                info.nft_address,
                info.nft_id,
                info.tick_lower,
                info.tick_upper,
                info.liquidity,
                info.share,
            )
        };
        let (ca, cb) = turbos_clmm::position_manager::decrease_liquidity_with_return_<
            CoinA,
            CoinB,
            FeeType,
        >(
            clmm_pool,
            positions,
            &mut wrapped_position.nft,
            delta_liquidity,
            min_amount_a,
            min_amount_b,
            clk.timestamp_ms() + 60000,
            clk,
            versioned,
            ctx,
        );
        let (_, _, new_liq) = turbos_clmm::position_manager::get_position_info(
            positions,
            nft_address,
        );
        assert_position_liquidity_valid(
            clmm_pool::get_pool_sqrt_price<CoinA, CoinB, FeeType>(clmm_pool),
            tick_lower,
            tick_upper,
            new_liq,
        );
        let new_share = update_position_liquidity(
            rewarder_manager,
            pool,
            wrapped_position,
            new_liq,
            clk,
        );
        emit(RemoveLiquidityEvent {
            pool_id: object::id<Pool>(pool),
            wrapped_position_id: wrapped_id,
            clmm_pool_id: pool.clmm_pool_id,
            nft_id,
            effective_tick_lower: pool.effective_tick_lower,
            effective_tick_upper: pool.effective_tick_upper,
            sqrt_price: pool.sqrt_price,
            old_liquidity,
            new_liquidity: new_liq,
            old_share,
            new_share,
        });
        (coin::into_balance<CoinA>(ca), coin::into_balance<CoinB>(cb))
    }

    public fun reward(info: &PositionRewardInfo): u128 { info.reward }

    public fun reward_debt(info: &PositionRewardInfo): u128 { info.reward_debt }

    public fun reward_harvested(info: &PositionRewardInfo): u64 { info.reward_harvested }

    public fun share(info: &WrappedPositionInfo): u128 { info.share }

    public fun sqrt_price(pool: &Pool): u128 { pool.sqrt_price }

    public fun is_effective_range_migrating(pool: &Pool): bool {
        pool.is_effective_range_migrating
    }

    public fun total_share(pool: &Pool): u128 { pool.total_share }

    public fun update_effective_tick_range<CoinA, CoinB, FeeType>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        clmm_pool: &CLMMPool<CoinA, CoinB, FeeType>,
        positions: &Positions,
        effective_tick_lower: I32,
        effective_tick_upper: I32,
        _sqrt_price: u128,
        start: vector<ID>,
        limit: u64,
        clk: &Clock,
        ctx: &TxContext,
    ): Option<ID> {
        config::checked_package_version(global_config);
        update_effective_tick_range_internal<CoinA, CoinB, FeeType>(
            global_config,
            rewarder_manager,
            pool,
            clmm_pool,
            positions,
            effective_tick_lower,
            effective_tick_upper,
            _sqrt_price,
            start,
            limit,
            clk,
            ctx,
        )
    }

    fun update_effective_tick_range_internal<CoinA, CoinB, FeeType>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        clmm_pool: &CLMMPool<CoinA, CoinB, FeeType>,
        positions: &Positions,
        eff_lower: I32,
        eff_upper: I32,
        _sqrt_price: u128,
        mut start: vector<ID>,
        limit: u64,
        clk: &Clock,
        ctx: &TxContext,
    ): Option<ID> {
        assert!(limit > 0, EMigrateLimitInvalid);
        config::check_pool_manager_role(global_config, tx_context::sender(ctx));
        let sqrt_price = clmm_pool::get_pool_sqrt_price<CoinA, CoinB, FeeType>(clmm_pool);
        check_effective_range(
            eff_lower,
            eff_upper,
            sqrt_price,
            clmm_pool::get_pool_tick_spacing<CoinA, CoinB, FeeType>(clmm_pool),
        );
        assert!(
            pool.clmm_pool_id == object::id<CLMMPool<CoinA, CoinB, FeeType>>(clmm_pool),
            EPoolCLmmPoolNotMatch,
        );
        pool.effective_tick_lower = eff_lower;
        pool.effective_tick_upper = eff_upper;
        pool.sqrt_price = sqrt_price;
        let mut cursor = if (vector::is_empty<ID>(&start)) {
            *linked_table::front<ID, WrappedPositionInfo>(&pool.positions)
        } else {
            assert!(vector::length<ID>(&start) == 1, EStartError);
            option::some<ID>(vector::pop_back<ID>(&mut start))
        };
        if (option::is_none<ID>(&cursor)) {
            pool.is_effective_range_migrating = false;
            return option::none<ID>()
        };
        pool.is_effective_range_migrating = true;
        let mut end_cursor = cursor;
        let mut ct = 0;
        let mut new_ts = pool.total_share;
        while (ct < limit && option::is_some<ID>(&cursor)) {
            let pid = *option::borrow<ID>(&cursor);
            let pi = linked_table::borrow_mut<ID, WrappedPositionInfo>(&mut pool.positions, pid);
            let (_, _, new_liq) = turbos_clmm::position_manager::get_position_info(
                positions,
                pi.nft_address,
            );
            let new_sh = calculate_position_share(
                pi.tick_lower,
                pi.tick_upper,
                new_liq,
                pool.sqrt_price,
                pool.effective_tick_lower,
                pool.effective_tick_upper,
            );
            let adj_ts = new_ts - pi.share;
            new_ts = adj_ts + new_sh;
            update_position_share(
                pi,
                rewarder::pool_rewards_settle(
                    rewarder_manager,
                    pool.rewarders,
                    object::id<CLMMPool<CoinA, CoinB, FeeType>>(clmm_pool),
                    clk,
                ),
                new_sh,
            );
            pi.effective_tick_lower = pool.effective_tick_lower;
            pi.effective_tick_upper = pool.effective_tick_upper;
            pi.sqrt_price = pool.sqrt_price;
            pi.liquidity = new_liq;
            cursor = *linked_table::next<ID, WrappedPositionInfo>(&pool.positions, pid);
            end_cursor = cursor;
            ct = ct + 1;
        };
        pool.total_share = new_ts;
        rewarder::set_pool_share(
            rewarder_manager,
            object::id<CLMMPool<CoinA, CoinB, FeeType>>(clmm_pool),
            pool.total_share,
        );
        pool.is_effective_range_migrating = option::is_some<ID>(&cursor);
        emit(UpdateEffectiveTickRangeEvent {
            pool_id: object::id<Pool>(pool),
            clmm_pool_id: object::id<CLMMPool<CoinA, CoinB, FeeType>>(clmm_pool),
            effective_tick_lower: eff_lower,
            effective_tick_upper: eff_upper,
            sqrt_price,
            start,
            end: end_cursor,
            limit,
        });
        cursor
    }

    public fun update_pool_allocate_point<RewardCoin>(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &Pool,
        allocate_point: u64,
        clock: &Clock,
        ctx: &TxContext,
    ) {
        config::checked_package_version(global_config);
        config::check_pool_manager_role(global_config, tx_context::sender(ctx));
        let rewarder_type = type_name::with_defining_ids<RewardCoin>();
        let old_allocate_point = rewarder::borrow_pool_allocate_point(
            rewarder_manager,
            rewarder_type,
            pool.clmm_pool_id,
        );
        rewarder::set_pool<RewardCoin>(
            rewarder_manager,
            pool.clmm_pool_id,
            allocate_point,
            clock,
        );
        emit(UpdatePoolAllocatePointEvent {
            pool_id: object::id<Pool>(pool),
            clmm_pool_id: pool.clmm_pool_id,
            old_allocate_point,
            new_allocate_point: allocate_point,
        });
    }

    fun update_position_liquidity(
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        wrapped_position: &WrappedPositionNFT,
        liquidity: u128,
        clk: &Clock,
    ): u128 {
        if (
            !linked_table::contains<ID, WrappedPositionInfo>(
                &pool.positions,
                object::id<WrappedPositionNFT>(wrapped_position),
            )
        ) return 0;
        let clmm_pool_id = position_nft::pool_id(&wrapped_position.nft);
        let info = linked_table::borrow_mut<ID, WrappedPositionInfo>(
            &mut pool.positions,
            object::id<WrappedPositionNFT>(wrapped_position),
        );
        info.liquidity = liquidity;
        let new_share = calculate_position_share(
            info.tick_lower,
            info.tick_upper,
            info.liquidity,
            pool.sqrt_price,
            pool.effective_tick_lower,
            pool.effective_tick_upper,
        );
        let adj_ts = pool.total_share - info.share + new_share;
        update_position_share(
            info,
            rewarder::pool_rewards_settle(
                rewarder_manager,
                pool.rewarders,
                clmm_pool_id,
                clk,
            ),
            new_share,
        );
        pool.total_share = adj_ts;
        rewarder::set_pool_share(rewarder_manager, clmm_pool_id, pool.total_share);
        new_share
    }

    fun update_position_share(
        info: &mut WrappedPositionInfo,
        reward_infos: VecMap<TypeName, u256>,
        new_share: u128,
    ) {
        let mut idx = 0;
        while (idx < vec_map::length<TypeName, u256>(&reward_infos)) {
            let (reward_type, acc_per_share) = vec_map::get_entry_by_idx<TypeName, u256>(
                &reward_infos,
                idx,
            );
            let old_reward_debt = position_reward_amount(info.share, *acc_per_share);
            let new_reward_debt = position_reward_amount(new_share, *acc_per_share);
            if (!vec_map::contains<TypeName, PositionRewardInfo>(&info.rewards, reward_type)) {
                vec_map::insert<TypeName, PositionRewardInfo>(
                    &mut info.rewards,
                    *reward_type,
                    PositionRewardInfo {
                        reward: old_reward_debt,
                        reward_debt: new_reward_debt,
                        reward_harvested: 0,
                    },
                );
            } else {
                let ri = vec_map::get_mut<TypeName, PositionRewardInfo>(
                    &mut info.rewards,
                    reward_type,
                );
                ri.reward = ri.reward + old_reward_debt - ri.reward_debt;
                ri.reward_debt = new_reward_debt;
            };
            idx = idx + 1;
        };
        info.share = new_share;
    }

    fun position_reward_amount(share: u128, acc_per_share: u256): u128 {
        (((share as u256) * acc_per_share / ACC_PRECISION) as u128)
    }

    public fun withdraw(
        global_config: &GlobalConfig,
        rewarder_manager: &mut RewarderManager,
        pool: &mut Pool,
        wrapped_position: WrappedPositionNFT,
        clk: &Clock,
    ): TurbosPositionNFT {
        config::checked_package_version(global_config);
        assert_not_effective_range_migrating(pool);
        assert!(object::id<Pool>(pool) == wrapped_position.pool_id, EPoolPositionNotMatch);
        let WrappedPositionNFT { id: nft_uid, pool_id: _, nft, url: _ } = wrapped_position;
        let inner_id = object::uid_to_inner(&nft_uid);
        object::delete(nft_uid);
        let clmm_pool_id = position_nft::pool_id(&nft);
        let mut removed_info = if (
            !linked_table::contains<ID, WrappedPositionInfo>(&pool.positions, inner_id)
        ) {
            let inv = dof::borrow_mut<String, PoolInvalidPositions>(
                &mut pool.id,
                utf8(b"invalid_pool_positions"),
            );
            linked_table::remove<ID, WrappedPositionInfo>(&mut inv.positions, inner_id)
        } else {
            linked_table::remove<ID, WrappedPositionInfo>(&mut pool.positions, inner_id)
        };
        let old_share = removed_info.share;
        update_position_share(
            &mut removed_info,
            rewarder::pool_rewards_settle(
                rewarder_manager,
                pool.rewarders,
                clmm_pool_id,
                clk,
            ),
            0,
        );
        pool.total_share = pool.total_share - old_share;
        rewarder::set_pool_share(rewarder_manager, clmm_pool_id, pool.total_share);
        let mut check_idx = 0;
        while (check_idx < vec_map::length<TypeName, PositionRewardInfo>(&removed_info.rewards)) {
            let (_, ri) = vec_map::get_entry_by_idx<TypeName, PositionRewardInfo>(
                &removed_info.rewards,
                check_idx,
            );
            assert!(ri.reward == 0, ERewarderNotHarvested);
            check_idx = check_idx + 1;
        };
        destroy_wrapping_position_info(removed_info);
        emit(WithdrawEvent {
            pool_id: object::id<Pool>(pool),
            wrapped_position_id: inner_id,
            clmm_pool_id,
            nft_id: position_nft::position_id(&nft),
            share: old_share,
        });
        nft
    }

    #[test_only]
    public fun new_pool_for_testing(
        clmm_pool_id: ID,
        effective_tick_lower: I32,
        effective_tick_upper: I32,
        sqrt_price: u128,
        ctx: &mut TxContext,
    ): Pool {
        Pool {
            id: object::new(ctx),
            clmm_pool_id,
            effective_tick_lower,
            effective_tick_upper,
            sqrt_price,
            total_share: 0,
            rewarders: vector::empty<TypeName>(),
            positions: linked_table::new<ID, WrappedPositionInfo>(ctx),
            is_effective_range_migrating: false,
        }
    }

    #[test_only]
    public fun set_effective_range_migrating_for_testing(pool: &mut Pool, migrating: bool) {
        pool.is_effective_range_migrating = migrating;
    }

    #[test_only]
    public fun assert_not_effective_range_migrating_for_testing(pool: &Pool) {
        assert_not_effective_range_migrating(pool);
    }

    #[test_only]
    public fun assert_fix_coin_amount_non_zero_for_testing(amount_a: u64, amount_b: u64) {
        assert!(amount_a > 0 || amount_b > 0, EPositionLiquidityInvalid);
    }

    #[test_only]
    public fun position_reward_amount_for_testing(share: u128, acc_per_share: u256): u128 {
        position_reward_amount(share, acc_per_share)
    }
}
