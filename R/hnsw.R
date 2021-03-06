## ensure module gets loaded
Rcpp::loadModule("HnswL2", TRUE)
Rcpp::loadModule("HnswCosine", TRUE)
Rcpp::loadModule("HnswIp", TRUE)

#' Find Nearest Neighbors and Euclidean Distances
#'
#' A k-nearest neighbor algorithm using the HNSW library
#' (\url{https://github.com/nmslib/hnsw}).
#'
#' This function also demonstrates how to use the minimal interface to HNSW to
#' do something non-trivial. The class used, "HnswL2", uses the "Squared L2"
#' distance, which is the square of the Euclidean distance. This function takes
#' care of the square root for you, so returns actual Euclidean distances.
#'
#' @param X a numeric matrix of data to add. Each of the n rows is an item in
#'   the index.
#' @param k Number of neighbors to return.
#' @param distance Type of distance to calculate. One of:
#' \itemize{
#'   \item \code{"l2"} Squared L2, i.e. squared Euclidean.
#'   \item \code{"euclidean"} Euclidean.
#'   \item \code{"cosine"} Cosine.
#'   \item \code{"ip"} Inner product: 1 - sum(ai * bi), i.e. the cosine distance
#'   where the vectors are not normalized. This can lead to negative distances
#'   and other non-metric behavior.
#' }
#' @param include_self If \code{TRUE}, return the item itself as one of its
#'   \code{k}-neighbors.
#' @param ef Controls the quality of the graph. Higher values lead to improved
#'   recall at the expense of longer build time. Suggested range: 100-2000
#'   (default: 200).
#' @param M Controls maximum number of neighbors in the zero and above-zero
#'   layers. Higher values lead to better recall and shorter retrieval times, at
#'   the expense of longer indexing time. Suggested range: 5-100 (default: 16).
#' @return a list containing:
#' \itemize{
#'   \item \code{idx} an n by k matrix containing the nearest neighbor indices.
#'   \item \code{dist} an n by k matrix containing the nearest neighbor
#'   Euclidean distances.
#' }
#' @examples
#' get_knn(as.matrix(iris[, -5]), k = 10)
get_knn <- function(X, k = 10, distance = "euclidean", include_self = TRUE,
                    M = 200, ef = 16) {

  distance <- match.arg(distance, c("l2", "euclidean", "cosine", "ip"))

  nr <- nrow(X)
  nc <- ncol(X)

  max_k <- ifelse(include_self, nr, nr - 1)
  if (k > max_k) {
    stop("k cannot be larger than ", max_k)
  }

  if (!include_self) {
    k <- k + 1
  }

  clazz <- switch(distance,
                  "l2" = RcppHNSW::HnswL2,
                  "euclidean" = RcppHNSW::HnswL2,
                  "cosine" = RcppHNSW::HnswCosine,
                  "ip" = RcppHNSW::HnswIp
                  )
  # Create the indexing object. You must say up front the number of items that
  # will be stored (nr).
  ann <- methods::new(clazz, nc, nr, M, ef)

  for (i in 1:nr) {
    # Items are added directly
    ann$addItem(X[i, ])
  }

  idx <- matrix(nrow = nr, ncol = k)
  dist <- matrix(nrow = nr, ncol = k)

  for (i in 1:nr) {
    # Neighbors are queried by passing the vector back in
    # To get distances as well as indices, use include_distances = TRUE
    res <- ann$getNNsList(X[i, ], k, include_distances = TRUE)
    idx[i, ] <- res$item
    dist[i, ] <- res$distance
  }

  if (!include_self) {
    idx <- idx[, -1]
    dist <- dist[, -1]
    k <- k - 1
  }

  if (distance == "euclidean") {
    dist <- sqrt(dist)
  }

  list(idx = idx, dist = dist)
}
