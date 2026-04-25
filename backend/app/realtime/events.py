from typing import Final


class EventName:
    RECIPE_TOKEN: Final = "recipe_token"
    RECIPE_COMPLETE: Final = "recipe_complete"
    IMAGE_READY: Final = "image_ready"
    CART_READY: Final = "cart_ready"
    SUBSTITUTION_PROPOSED: Final = "substitution_proposed"
    ORDER_STATUS: Final = "order_status"
    MEAL_PLAN_READY: Final = "meal_plan_ready"
    ERROR: Final = "error"
    PING: Final = "ping"
