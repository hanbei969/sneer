library(sneer)
context("Perplexity")

presult <- d_to_p_perp_bisect(distance_matrix(range_scale_matrix(iris[, 1:4])),
                              weight_fn = sqrt_exp_weight, perplexity = 50,
                              verbose = FALSE)
sigmas <- 1 / sqrt(presult$beta * 2)

test_that("distribution of sigmas is ok", {
  expect_equal(min(sigmas), 0.1268, tolerance = 0.00005, scale = 1)
  expect_equal(median(sigmas), 0.1694, tolerance = 0.00005, scale = 1)
  expect_equal(mean(sigmas), 0.1717, tolerance = 0.00005, scale = 1)
  expect_equal(max(sigmas), 0.2187, tolerance = 0.00005, scale = 1)
})

test_that("distribution of P is ok", {
  expect_equal(min(presult$pm), 2.22e-16)
  expect_equal(median(presult$pm), 0.0006403, tolerance = 5e-8, scale = 1)
  expect_equal(mean(presult$pm), 0.006667, tolerance = 5e-7, scale = 1)
  expect_equal(max(presult$pm), 0.1286, tolerance = 5e-5, scale = 1)
})

presult_exp <- d_to_p_perp_bisect(distance_matrix(iris[, 1:4]),
                              weight_fn = exp_weight,
                              perplexity = 50,
                              verbose = FALSE)

test_that("distribution of intrinsic dimensionality is ok", {
  expect_equal(min(presult_exp$dim), 0.2734, tolerance = 1e-3)
  expect_equal(median(presult_exp$dim), 1.086, tolerance = 1e-3)
  expect_equal(mean(presult_exp$dim), 0.9939, tolerance = 1e-3)
  expect_equal(max(presult_exp$dim), 2.657, tolerance = 1e-3)
})


test_that("manual per-point perplexity", {
  # perplexity 3
  iris10_u3 <- sneer(iris[1:10, ], ret = c("p"), perplexity = 3, method = "asne",
                     max_iter = 0, plot_type = NULL)
  # perplexity 5
  iris10_u5 <- sneer(iris[1:10, ], ret = c("p"), perplexity = 5, method = "asne",
                     max_iter = 0, plot_type = NULL)
  # 1-5 have perplexity 3, 6-10 have perplexity 5
  iris10_u35 <- sneer(iris[1:10, ], ret = c("p"),
                      perplexity = c(rep(3, 5), rep(5, 5)), method = "asne",
                      max_iter = 0, plot_type = NULL)
  expect_equal(iris10_u35$p[1:5, ], iris10_u3$p[1:5, ])
  expect_equal(iris10_u35$p[6:10, ], iris10_u5$p[6:10, ])
})
