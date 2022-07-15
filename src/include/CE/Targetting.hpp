#ifndef TARGETTING_HPP
#define TARGETTING_HPP


namespace godot {
  namespace CE {
    class select_flying {
      // Filter for target selection logic. Allows only ships that are
      // not leaving the system nor already gone.
    public:
      select_flying() {};
      template<class I>
      real_t operator () (I iter) const {
        if(iter->second.fate)
          return 0;
        else
          return 1e-5;
      }
    };
    
    template<class F,class C>
    object_id select_target(const typename C::key_type &start,const F &selection_function,
                            const C&container, bool first, real_t start_weight=1.0f) {
      typename C::const_iterator start_p = container.find(start);
      typename C::const_iterator best = start_p;
      typename C::const_iterator next = best;
      
      if(start_p==container.end()) {
        next=container.begin();
      } else {
        next++;
      }

      real_t best_score = 0;

      typename C::const_iterator it=next;
      do {
        if(it==container.end())
          it=container.begin();
        else {
          real_t result = selection_function(it);
          if(it==start_p)
            result *= start_weight;
          if(result>best_score) {
            best_score=result;
            best=it;
            if(first)
              break;
          }
          it++;
        }
      } while(it!=next);

      return best==container.end() ? -1 : best->first;
    }

    class select_mask {
      const int mask;
    public:
      select_mask(int mask): mask(mask) {}
      select_mask(const select_mask &other): mask(other.mask) {}
      template<class I>
      inline real_t operator () (I iter) const {
        return (iter->second.collision_layer & mask) ? 1e-5 : 0;
      }
    };

    class select_nearest {
      const Vector3 to;
      mutable real_t closest;
      const real_t max_range_squared, near_range;
    public:
      select_nearest(const Vector3 &to,real_t max_range = std::numeric_limits<real_t>::infinity(),real_t near_range = 10.0f):
        to(to),
        closest(std::numeric_limits<real_t>::infinity()),
        max_range_squared(max_range*max_range),
        near_range(std::max(1.0e-5f,near_range))
      {}
      select_nearest(const select_nearest &other):
        to(other.to), closest(other.closest),
        max_range_squared(other.max_range_squared),
        near_range(other.near_range)
      {}
      template<class I>
      real_t operator () (I iter) const {
        real_t distance_squared = distsq(to,iter->second.position);
        if(distance_squared>max_range_squared)
          return 0;
        else
          return 1/(near_range+sqrtf(distance_squared));
      }
    };

    template<class A,class B>
    class select_two {
      const A one;
      const B two;
    public:
      select_two(const A &one,const B&two):
        one(one), two(two)
      {}
      select_two(const select_two &other):
        one(other.one), two(other.two)
      {}
      template<class I>
      real_t operator () (I iter) const {
        real_t result_one=one(iter);
        if(result_one) {
          real_t result_two=two(iter);
          if(result_two)
            return result_one+result_two;
        }
        return 0;
      }
    };
    
    template<class A,class B,class C>
    class select_three {
      const A one;
      const B two;
      const C three;
    public:
      select_three(const A &one,const B&two,const C&three):
        one(one), two(two), three(three)
      {}
      select_three(const select_three &other):
        one(other.one), two(other.two), three(other.three)
      {}
      template<class I>
      real_t operator () (I iter) const {
        real_t result_one=one(iter);
        if(result_one) {
          real_t result_two=two(iter);
          if(result_two) {
            real_t result_three=three(iter);
            if(result_three)
              return result_one+result_two+result_three;
          }
        }
        return 0;
      }
    };
  }
}


#endif
