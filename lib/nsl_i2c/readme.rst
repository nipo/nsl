=====
 I2C
=====

* I2C masters

  * `from lumped signals <master>`_.

  * `from a command/response stream <transactor>`_.

* I2C slave

  * `With local clock <clocked>`_,

  * `Without local clock <clockfree>`_,

* I2C chip drivers for abstract usage

  * GPIO extender transactors (`PCA8574 <nsl_i2c/pca8574>`_, `PCA9534A
    <nsl_i2c/pca9534a>`_, `PCA9555 <nsl_i2c/pca9555>`_, `PCAL6524 <nsl_i2c/pcal6524>`_),

  * PLL initializer (`SI5351 <nsl_silabs/si5351>`_),

  * ADC drivers (`PCT2075 <nsl_i2c/pct2075>`_),

  * DAC drivers (`MCP4726 <nsl_i2c/mcp4726>`_),

  * LED drivers (`IS31FL3731 <nsl_i2c/is31fl3731>`_).
