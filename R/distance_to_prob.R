# Probability Matrices
#
# For probability-based embedding, sneer works with three types of probability
# matrix.
#
# @section Row Probabilities:
# Matrix contains N different probability distributions, where N is the number
# of rows (or columns). Each row sums to one. This structure is called a row
# stochastic matrix when used in Markov Chains.
#
# In the context of embedding, this structure represents a point-based
# probability: a given entry \code{P[i, j]} should be considered the
# conditional probability pj|i, the probability that point j is a neighbor of
# i, given that i has been picked as the reference point.
#
# Given the potentially different inhomogeneous distribution of points
# in a data set, there is therefore no reason that \code{P[i, j]} should be
# equal to \code{P[j, i]}: the probability that point i is a neigbour of point
# j is not necessarily the same that j is a neighbor of i.
#
# Row probability is the model used in the original (asymmetric) Stochastic
# Neighbor Embedding paper.
#
# In sneer, row probability matrices should be given a \code{type} attribute
# with value \code{row}.
#
# @section Joint Probabilities:
# Matrix contains 1 probability distribution. The grand sum of the matrix is
# one.
#
# In the context of embedding, this structure represents a pair-based
# probability: a given entry \code{P[i, j]} should be considered the
# joint probability pij, the probability that point i and point j are selected
# as a pair. From this point of view, whether the pair is represented as
# \code{P[i, j]} or \code{P[j, i]} should be irrelevant. Therefore a joint
# probability is symmetric.
#
# Joint probability is the model used in Symmetric Stochastic Neighbor
# Embedding and t-Distributed Stochastic Neighbor Embedding. Although both
# methods use the same techniques and procedures as ASNE, they introduce
# further steps to process the input probability, which they convert from a
# row probability form to a joint probability by taking the average of
# \code{P[i, j]} and \code{P[j, i]} and then renormalizing. The output
# probabilities don't require the averaging step, because the weight function
# used in SSNE and t-SNE is symmetric. Only the normalization step is required.
#
# In sneer, joint probability matrices should be given a \code{type} attribute
# with value \code{joint}.
#
# @section Conditional Probabilities:
# An intermediate step between a row probability matrix and a joint probability
# matrix. The matrix contains 1 probability distribution. The grand sum of the
# matrix is one.
#
# In the context of embedding, this structure represents a pair-based
# probability: a given entry \code{P[i, j]} should be considered the
# conditional probability pj|i, the probability that point i and point j are
# selected as a pair, given that point i was selected first.
#
# Unlike the joint probability, there is no restriction that \code{P[i, j]} be
# equal to \code{P[j, i]}. The question is whether you can justify that making
# sense in your model of embedding.
#
# No embedding I'm aware of uses conditional probabilities directly. However,
# the output probabilities in SSNE and t-SNE could be thought of as a special
# case of a conditional matrix: yes, the output \code{P[i, j]} is equal to
# \code{P[j, i]}, so they're technically joint probabilities, but no special
# effort was made to make them joint, unlike their counterpart matrices in
# the input case: those need to be explicitly normalized and then symmetrized.
# The jointness of the output probabilities in SSNE and t-SNE is entirely a
# by-product of the symmetric nature of the weighting function used to generate
# the similarities. In SSNE, if the beta parameter was allowed to vary between
# points in the output probability, for example, then the resulting matrix
# would have to be symmetrized to be a joint probability (note also that the
# stiffness matrix function would have to be rewritten!).
#
# In sneer, joint probability matrices should be given a \code{type} attribute
# with value \code{joint}.
#
# @examples
# \dontrun{
# # Setting the row probability type
# prow <- some_func()
# attr(prow, "type") <- "row"
#
# # # Setting the joint probability type
# pjoint <- some_other_func()
# attr(pjoint, "type") <- "joint"
#
# # Setting the conditional probability type
# pcond <- yet_another_func()
# attr(pcond, "type") <- "cond"
# }
# @keywords internal
# @name probability_matrices
NULL

# Output Update Function
#
# Embedding methods can specify which matrices created as part of mapping from
# embedded coordinates to the output probabilities they want to keep. The
# squared distances (\code{d2m}) are not always useful, except if the plugin
# gradient is being used to calculate the stiffness matrix. The weight matrix
# (\code{wm}) is used by the plugin gradient method and by some non-plugin
# method stiffness functions (e.g. \code{tsne} or \code{hssne}). The output
# probability (\code{qm}) is an integral part of all cost functions and
# gradients so should always be retained.
#
# @param keep List containing any or all of the following matrix names:
# \describe{
#  \item{\code{d2m}}{Output squared distances matrix.}
#  \item{\code{wm}}{Output weight matrix.}
#  \item{\code{qm}}{Output probability matrix.}
#  \item{\code{qcm}}{Output conditional probability matrix, before any averaging
#  (if any) is applied.}
# }
# @return List containing updated output data with all the matrices specified
# by \code{keep} added to it.
update_out_prob <- function(inp, out, method) {
  res <- update_probs(out, method)

  keep <- method$out_keep
  for (i in 1:length(keep)) {
    # Special case if we ask to keep distance matrix
    # By default we create squared distances only and save on a sqrt
    # unless needed
    if (keep[[i]] == "dm") {
      if (is.null(res$dm)) {
        if (method$transform$name == "d2") {
          out$dm <- sqrt(res$d2m)
        }
        else {
          out$dm <- sqrt(coords_to_dist2(out$ym))
        }
      }
      else {
        # In some cases, e.g. if we were doing the no-transform, we have dm to
        # hand already without extra computation (it's also d2m in that case,
        # but this is clearer)
        out$dm <- res$dm
      }
    }
    else {
      out[[keep[i]]] <- res[[keep[i]]]
    }
  }

  out <- out_updated(inp, out, method)
  list(out = out)
}


# Triggered after update_out
# Looks for out_updated_fn, e.g. storage of extra data
out_updated <- function(inp, out, method) {
  if (!is.null(method$out_updated_fn)) {
    out <- method$out_updated_fn(inp, out, method)
  }
  if (!is.null(method$cost$out_updated_fn)) {
    out <- method$cost$out_updated_fn(inp, out, method)
  }
  if (!is.null(method[["stiffness"]]) &&
      !is.null(method[["stiffness"]]$out_updated_fn)) {
    out <- method$stiffness$out_updated_fn(inp, out, method)
  }
  out
}

# Update Output Probabilities
#
# Calculates the output probabilities based on the current embedding
# coordinates.
#
# Intermediate data (squared distance matrix and weight matrix) may be useful
# in calculating the gradient, so is also returned from this function.
#
# Some embedding techniques (e.g. multiscale perplexity approaches) calculate
# the output probabilities from multiple values based using several different
# similarity kernels to produce different weight matrices. The squared distance
# matrix is the same in all cases, so it can be calculated once and then passed
# to this function as an optional parameter, avoiding recalculating multiple
# times.
#
# @param out Output data.
# @param method Embedding method.
# @param d2m Optional squared distance matrix, if the same embedding
# coordinate configuration is to be used for multiple weight or probability
# calculations.
# @return List containing:
#  \item{\code{d2m}}{Matrix of squared distances.}
#  \item{\code{wm}}{Weight matrix.}
#  \item{\code{qm}}{Probability Matrix.}
#  \item{\code{qcm}}{Conditional Probability Matrix. Non-null only if an
#  asymmetric kernel is used and the embedding method uses a joint
#  probability matrix.}
update_probs <- function(out, method, d2m = NULL,
                         kernel = method$kernel, prob_type = NULL) {

  dm <- NULL
  # This code block attempts to avoid calculating or storing the distance
  # matrix unless it's really needed.
  if (is.null(d2m)) {
    if (!is.null(method$transform$fn)) {
      res <- method$transform$fn(out, method)
      d2m <- res$fm
      # In the no-transform case, we calculate fm and dm are the same, so
      # there's no harm in storing them
      if (!is.null(res$dm)) {
        dm <- res$dm
      }
    }
    else {
      d2m <- coords_to_dist2(out$ym)
    }
  }

  if (!is.null(method$kernel)) {
    wm <- dist2_to_weights(d2m, kernel)
  }
  else {
    wm <- d2m
  }

  res <- weights_to_probs(wm, method, prob_type)
  list(d2m = d2m, wm = wm, qm = res$pm, qcm = res$pcm, dm = dm)
}

# Squared (Euclidean) Distance Matrix
#
# Creates a matrix of squared Euclidean distances from a coordinate matrix.
#
# Probability-based embedding techniques use the squared Euclidean distance
# as input to their weighting functions.
#
# @param xm a matrix of coordinates
# @return Squared distance matrix.
coords_to_dist2 <- function(xm) {
  sumsq <- apply(xm ^ 2, 1, sum)  # sum of squares of each row of xm
  d2m <- -2 * xm %*% t(xm)  # cross product
  d2m <- sweep(d2m, 2, -t(sumsq))  # adds sumsq[j] to D2[i,j]
  d2m <- sumsq + d2m  # add sumsq[i] to D2[i,j]
  d2m[d2m < 0] <- 0
  d2m
}

# Transform distances by squaring them
# It's less work to calculate d2 than d, so we probably have already
# calculated this and pass it as an extra parameter.
d2_transform <- function() {
  list(
    fn = function(out, method, d2m = NULL, mat_name = "ym") {
      if (!is.null(d2m)) {
        list(fm = d2m)
      }
      else {
        # Safe only if passed out = inp when input is a distance matrix
        # out$dm is otherwise likely dm from a previous iteration
        if (is.null(out[[mat_name]])) {
          list(fm = out$dm * out$dm)
        }
        else {
          list(fm = coords_to_dist2(out[[mat_name]]))
        }
      }
    },
    gr = function(inp, out, method) {
      2 * out$dm
    },
    name = "d2"
  )
}

# No transform.
# Conceptually does no work as we map directly from D -> F
# But squared distances are the usual transform in the SNE case and has the
# advantage of avoiding a sqrt calculation, so raw distances actually has a
# cost.
no_transform <- function() {
  list(
    # The embedding gradient expression that arises from the use of raw
    # distances is very likely to need the raw distance explicitly, so store
    # it separately from the "transformed" matrix in the result.
    fn = function(out, method, d2m = NULL, mat_name = "ym") {
      if (!is.null(d2m)) {
        fm <- sqrt(d2m)
      }
      else {
        # Rarely, out might actually be inp and have dm pre-calculated
        # Safe only if passed out = inp when input is a distance matrix
        # out$dm is otherwise likely dm from a previous iteration
        # If coordinates are present, use them
        if (is.null(out[[mat_name]])) {
          fm <- out$dm
        }
        else {
          fm <- sqrt(coords_to_dist2(out[[mat_name]]))
        }
      }
      list(fm = fm, dm = fm)
    },
    gr = function(inp, out, method) {
      1
    },
    name = "none"
  )
}

# Create Weight Matrix from Squared Distances
#
# Weights are subsequently normalized to probabilities in probability-based
# embedding. This function guarantees that the self-weight is 0.
#
# @param d2m Matrix of squared distances.
# @param kernel Function with signature \code{weight_fn(d2m)} where
# \code{d2m} is a matrix of squared distances.
# @return Weights matrix. The diagonal (i.e. self-weight) is enforced to be
# zero.
dist2_to_weights <- function(d2m, kernel) {
  if (is.null(attr(kernel$fn, "type"))) {
    stop("kernel fn must have type attribute")
  }
  wm <- kernel$fn(kernel, d2m)
  diag(wm) <- 0  # set self-weights to 0
  attr(wm, "type") <- attr(kernel$fn, "type")
  wm
}

# Weight Matrix to Probability Matrix Conversion
#
# Given a weight matrix and an embedding method, this function creates a
# probability matrix.
#
# @param wm Weight Matrix. Must have a "type" attribute with one of the
#   following values:
#   \describe{
#   \item{"symm"}{A symmetric matrix.}
#   \item{"asymm"}{An asymmetric matrix.}
#   }
# @param method Embedding method.
# @return List containing:
#  \item{\code{pm}}{Probability matrix of the type required by the embedding
#  method.}
#  \item{\code{pcm}}{Conditional Probability Matrix. Non-null only if an
#  asymmetric kernel is used and the embedding method uses a joint
#  probability matrix.}
weights_to_probs <- function(wm, method, prob_type = NULL) {

  # Allows for P to be joint and Q to be conditional
  # (only matters for methods with asymmetric kernels, where joint-izing
  # the output probabilities requires an extra step and hence change to
  # the gradient)
  # ASSUMPTION: assumes that weights_to_probs is only used by output distances
  # and not input probability calibration, unless a non-null prob_type is passed
  if (is.null(prob_type)) {
    if (!is.null(method$out_prob_type)) {
      prob_type <- method$out_prob_type
    }
    else {
      prob_type <- method$prob_type
    }
  }

  if (prob_type == "joint") {
    weight_type <- attr(wm, "type")
    if (is.null(weight_type)) {
      stop("W matrix must have type attribute defined")
    }
    prob_fn_name <- paste0(weight_type, "_weights_to_p", prob_type)
  }
  else {
    prob_fn_name <- paste0("weights_to_p", prob_type)
  }

  prob_fn <- get(prob_fn_name)
  if (is.null(prob_fn)) {
    stop("No ", prob_fn_name, " function defined for weight to probability ",
         "matrix conversion")
  }
  res <- get(prob_fn_name)(wm)
  attr(res$pm, "type") <- prob_type
  if (!is.null(res$pc)) {
    attr(res$pc, "type") <- "cond"
  }

  res
}

# Create Row Probability Matrix from Weight Matrix
#
# Used in ASNE. The probability matrix is such that all elements are positive
# and each row sums to 1.
#
# @param wm Matrix of weighted distances.
# @return A list containing
#  \item{pm}{Row probability matrix.}
weights_to_prow <- function(wm) {
  row_sums <- rowSums(wm) + .Machine$double.eps
  pm <- sweep(wm, 1, row_sums, "/")
  list(pm = pm)
}

# Create Conditional Probability Matrix from Weight Matrix
#
# A weight to probability function.
#
# Creates a conditional probability matrix: the grand sum of the elements are
# one, but does not have to be symmetric. The weight matrix can be symmetric
# or asymmetric.
#
# @param wm Matrix of weighted distances. Asymmetric or symmetric.
# @return A list containing
#  \item{pm}{Conditional probability matrix.}
weights_to_pcond <- function(wm) {
  pm <- wm / sum(wm) + .Machine$double.eps
  list(pm = pm)
}

weights_to_pun <- function(wm) {
  list(pm = wm)
}

# Create Joint Probability Matrix from Symmetric Weight Matrix
#
# A weight to probability function.
#
# Creates a joint probability matrix: the grand sum of the elements are
# one, and the matrix is symmetric. The weight matrix must be symmetric. Used
# in SSNE and t-SNE to generate the output probabilities.
#
# @param wm Symmetric matrix of weighted distances.
# @return List containing:
# \item{pm}{Joint probability matrix.}
symm_weights_to_pjoint <- weights_to_pcond

# Create Joint Probability Matrix from Asymmetric Weight Matrix
#
# A weight to probability function.
#
# Creates a joint probability matrix: the grand sum of the elements are
# one, and the matrix is symmetric. The weight matrix should be asymmetric.
# A symmetric matrix is also a valid input, but it's more efficient to use
# \code{symm_weights_to_pjoint}.
#
# The joint probability matrix is created by averaging \code{p[i, j]} and
# \code{p[j, i]} of the conditional probability matrix formed by normalizing
# the weights matrix over the sum of all elements.
#
# @param wm Asymmetric matrix of weighted distances.
# @return Joint probability matrix.
# @return List containing:
# \item{pm}{Joint probability matrix.}
# \item{pcm}{Conditional probability matrix}
asymm_weights_to_pjoint <- function(wm) {
  pcm <- weights_to_pcond(wm)$pm
  pm <- symmetrize_matrix(pcm)
  list(pm = pm, pcm = pcm)
}

# Convert Row Probability Matrix to a Conditional Probability Matrix
#
# Given a row probability matrix (elements of each row are non-negative and
# sum to one), this function scales each element by the sum of the matrix so
# that the elements of the entire matrix sum to one.
#
# An intermediate step in creating joint probabilities from row probabilities.
#
# @param prow Row probability matrix.
# @return Conditional probability matrix.
prow_to_pcond <- function(prow) {
  prow / sum(prow)
}

# Convert Row Probability Matrix to a Joint Probability Matrix
#
# Given a row probability matrix (elements of each row are non-negative and
# sum to one), this function scales each element by such that the elements of
# the entire matrix sum to one, and that the matrix is symmetric, i.e.
# \code{p[i, j] = p[j, i]}.
#
# Used in \code{ssne}, \code{tsne} and related methods to convert
# input probabilities.
#
# @param prow Row probability matrix.
# @return Joint probability matrix.
prow_to_pjoint <- function(prow) {
  symmetrize_matrix(prow_to_pcond(prow))
}

# Renormalize Row Probability Matrix
#
# Convert row probability matrix to a joint probability then back to row.
#
# Given a row probability matrix (elements of each row are non-negative and
# sum to one), this function scales each element by such that the elements of
# the entire matrix sum to one, and that the matrix is symmetric, i.e.
# \code{p[i, j] = p[j, i]}. Then it converts back to a row probability matrix
# but normalizing with respect to each row sum.
#
# This attempts to borrow the idea of averaging pi|j and pj|i but still keeping
# the row-based matrices of point-based normalization.
prow_to_pavrow <- function(prow) {
  weights_to_prow(prow_to_pjoint(prow))$pm
}

# Symmetric Matrix from Square Matrix
#
# The matrix is symmetrized by setting \code{pm[i, j]} and \code{pm[j, i]} to
# their average, i.e. \code{Pij} = \code{(Pij + Pji)/2} = \code{Pji}.
#
# In SSNE and t-SNE, this is used as part of the process of converting the row
# stochastic matrix of conditional input probabilities to a joint probability
# matrix.
#
# @param pm Square matrix to symmetrize.
# @return Symmetrized matrix such that \code{pm[i, j]} = \code{pm[j, i]}
symmetrize_matrix <- function(pm) {
  0.5 * (pm + t(pm))
}

# Probability Type Conversion
#
# Given a probability matrix and an embedding method, this function applies
# a conversion from the type of the probability matrix into that required
# by the embedding method.
#
# @param pm Probability Matrix. Must have a "type" attribute with one of the
#   following values:
#   \describe{
#   \item{"row"}{A probability where each row sums to one.}
#   \item{"cond"}{A conditional probablilty matrix where the grand sum of the
#   entire matrix is 1.}
#   \item{"joint"}{A joint probability matrix where the grand sum of the entire
#   matrix is 1, and \code{pm[i, j]} = \code{pm[j, i]} for all pairs i and j.}
#   }
#   See \code{probability_matrices} for more details.
# @param method Embedding method, which must have a "type" attribute with one
#   of the values described for \code{pm}. This represents the type of
#   probability matrix that \code{pm} will be converted into.
# @return Converted probability matrix.
handle_prob <- function(pm, method) {
  prob_in <- attr(pm, "type")
  if (is.null(prob_in)) {
    stop("P matrix must have type attribute defined")
  }

  prob_out <- method$prob_type
  if (prob_in != prob_out) {
    prob_fn_name <- paste0("p", prob_in, "_to_p", prob_out)
    prob_fn <- get(prob_fn_name)
    if (is.null(prob_fn)) {
      stop("No ", prob_fn_name, " function defined for probability matrix
           conversion")
    }
    pm <- get(prob_fn_name)(pm)
    attr(pm, "type") <- prob_out
  }
  pm
}

# TRUE if the output probabilities are joint
# If you are using an asymmetric kernel (i.e. there are per-point parameters
# which aren't guaranteed to be uniform), you will need to take extra steps
# to enforce jointness.
# see also is_asymmetric_kernel
is_joint_out_prob <- function(method) {
  if (is.null(method$out_prob_type)) {
    method$prob_type == "joint"
  }
  else {
    # This should probably never happen because it implies we want the input
    # probabilities to be conditional, but to enforce jointness of the output
    # if needed
    method$out_prob_type == "joint"
  }
}

# An embedding method is fully symmetric if the kernel is symmetric, and the
# input probability is joint, which implies that the output probability is
# either also joint or marked as conditional. However, because the kernel is
# symmetric the output probability is already joint, and hence requires no
# extra averaging. This means that pi|j = pj|i = pij and likewise for Q and
# the symmetrized SSNE-like gradient simplifications hold
is_fully_symmetric_embedding <- function(method) {
  is_symmetric_kernel(method$kernel) && method$prob_type == "joint"
}

# The output probability is "enforced joint" if it's marked as being joint, but
# the kernel is asymmetric. In this case an extra averaging step is needed to
# convert the weights to joint probabilities. This rules out some simplified
# stiffness expressions.
is_enforced_joint_out_prob <- function(method) {
  is_joint_out_prob(method) && is_asymmetric_kernel(method$kernel)
}
