library vunit_lib;
context vunit_lib.vunit_context;

entity tb_pass is
  generic (runner_cfg : string);
end entity;

architecture sim of tb_pass is
begin
  main : process
  begin
    test_runner_setup(runner, runner_cfg);
    check_equal(1 + 1, 2);
    test_runner_cleanup(runner);
  end process;
end architecture;
